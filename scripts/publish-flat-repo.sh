#!/usr/bin/env bash
# Maintain a "flat" apt repository as assets of a GitHub release.
#
# GitHub Pages (gh-pages) is a git branch and rejects files >100MB - the
# trixie kernel image crossed that. Release assets allow 2GB, and a flat
# apt repo resolves `Filename:` relative to the repo base URL, so the
# release download URL itself serves as the repository:
#
#   deb https://github.com/<owner>/<repo>/releases/download/apt-repo-<distro>/ ./
#
# usage: publish-flat-repo.sh <distro> <deb> [<deb>...]
#
# The release accumulates debs across runs (old kernel versions stay
# installable); the index is always regenerated over the full asset set.
# Requires: gh (authenticated), apt-ftparchive, gpg, and APT_SIGNING_KEY
# (+ optionally APT_SIGNING_KEY_PASSPHRASE) in the environment.
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 <distro> [deb...]" >&2; exit 2; }
distro="$1"; shift
tag="apt-repo-${distro}"

if [ -n "${GITHUB_REPOSITORY:-}" ]; then
  repo="${GITHUB_REPOSITORY}"
else
  repo="$(git remote get-url origin | sed -E 's|.*github\.com[:/]||; s|\.git$||')"
fi
work="$(mktemp -d)"; trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/pool"

if ! gh release view "${tag}" --repo "${repo}" >/dev/null 2>&1; then
  gh release create "${tag}" --repo "${repo}" \
    --title "apt repository (${distro})" \
    --notes "Flat apt repository for Debian ${distro} - the assets ARE the repository. See README."
fi

# Download every deb already published so the rebuilt index covers them
# (deb filenames embed the version, so identical names = identical files).
gh release view "${tag}" --repo "${repo}" --json assets \
  --jq '.assets[].name | select(endswith(".deb"))' > "${work}/assets" || true
while read -r a; do
  [ -n "${a}" ] || continue
  gh release download "${tag}" --repo "${repo}" -p "${a}" --dir "${work}/pool" --clobber
done < "${work}/assets"

new_files=()
for f in "$@"; do
  [ -e "${f}" ] || continue
  b="$(basename "${f}")"
  cp "${f}" "${work}/pool/${b}"
  grep -qx "${b}" "${work}/assets" || new_files+=("${f}")
done

if ! compgen -G "${work}/pool/*.deb" >/dev/null; then
  echo "no debs for ${distro}; nothing to publish"
  exit 0
fi

# Index over the complete pool. Filenames stay bare so they resolve to
# <base>/<asset-name> - the release download URL.
(
  cd "${work}/pool"
  dpkg-scanpackages --multiversion . 2>/dev/null \
    | sed 's|^Filename: \./|Filename: |' > Packages
  gzip -9c Packages > Packages.gz
  apt-ftparchive \
    -o "APT::FTPArchive::Release::Origin=aufs-dkms-build" \
    -o "APT::FTPArchive::Release::Label=aufs-dkms-build" \
    -o "APT::FTPArchive::Release::Codename=${distro}" \
    -o "APT::FTPArchive::Release::Architectures=amd64 all" \
    release . > Release
)

export GNUPGHOME="${work}/gnupg"
mkdir -m 700 -p "${GNUPGHOME}"
printf '%s' "${APT_SIGNING_KEY:?APT_SIGNING_KEY required}" | gpg --batch --quiet --import
keyid="$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1=="sec"{print $5; exit}')"
sign() {
  gpg --batch --yes --pinentry-mode loopback \
    --passphrase "${APT_SIGNING_KEY_PASSPHRASE:-}" --local-user "${keyid}" "$@"
}
sign --detach-sign --armor -o "${work}/pool/Release.gpg" "${work}/pool/Release"
sign --clearsign -o "${work}/pool/InRelease" "${work}/pool/Release"
gpg --batch --export "${keyid}" > "${work}/pool/public.key"

# Debs first, index last - the repo is never half-published.
for f in "${new_files[@]}"; do
  gh release upload "${tag}" --repo "${repo}" "${f}"
done
for i in Packages Packages.gz Release Release.gpg InRelease public.key; do
  gh release upload "${tag}" --repo "${repo}" --clobber "${work}/pool/${i}"
done

echo "published: https://github.com/${repo}/releases/download/${tag}/ ($(ls "${work}/pool"/*.deb | wc -l) debs)"
