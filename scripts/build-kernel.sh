#!/usr/bin/env bash
#
# Build aufs-enabled Debian kernel packages (linux-image / linux-headers)
# for Debian releases whose stock kernels no longer export the symbols
# aufs requires (everything newer than buster's 4.19).
#
# The result is a flavour "aufs-amd64" of the regular Debian kernel:
# upstream aufs{5,6}-{base,mmap,standalone}.patch provide the required
# EXPORT_SYMBOL_GPL()s, while aufs itself stays in the aufs-dkms package.
#
# Usage: build-kernel.sh <debian-flavor>
#        e.g.  build-kernel.sh trixie | bookworm | bullseye
#
# Environment:
#   WORK_DIR        directory for source + output packages (default: /src)
#   KERNEL_CONFIG   repo dir with per-series assets (default:
#                   <repo>/scripts/kernel)
#   DEB_BUILD_OPTIONS, DEB_BUILD_PROFILES are honoured (profiles default
#                   to "nodoc"). NOTE: pkg.linux.notools is NOT usable —
#                   it also disables linux-kbuild, which the headers
#                   package depends on.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_CONFIG="${KERNEL_CONFIG:-${SCRIPT_DIR}/kernel}"
WORK_DIR="${WORK_DIR:-/src}"
# nodoc skips the -doc packages; noudeb skips debian-installer udebs
# (bullseye's udeb packaging expects the stock flavour names).
export DEB_BUILD_PROFILES="${DEB_BUILD_PROFILES:-nodoc noudeb}"

usage() {
    echo "usage: $0 <debian-flavor>" >&2
    echo "  flavors: bullseye (5.10), bookworm (6.1), trixie (6.12)" >&2
    exit 2
}

[ $# -eq 1 ] || usage
DEB_FLAVOR="$1"
case "${DEB_FLAVOR}" in
    bullseye|bookworm|trixie) ;;
    *) usage ;;
esac

# ----------------------------------------------------------------------------
# 1. Build dependencies + deb-src entries
# ----------------------------------------------------------------------------

# deb822 sources (bookworm/trixie): Types: deb -> deb deb-src
for f in /etc/apt/sources.list.d/*.sources; do
    [ -e "$f" ] || continue
    sed -i 's/^Types: deb$/Types: deb deb-src/' "$f"
done
# classic sources (buster/bullseye archive + snapshot lines); skip files
# that already carry deb-src entries (our docker images do)
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
    [ -e "$f" ] || continue
    grep -q '^deb ' "$f" || continue
    grep -q '^deb-src ' "$f" && continue
    sed -n 's/^deb /deb-src /p' "$f" >> "$f"
done

apt-get update -qq
# Full Build-Depends including the tools stack: linux-kbuild is required
# by the headers package and lives behind <!pkg.linux.notools>, so the
# tools build-deps cannot be profiled away.
DEB_BUILD_PROFILES='' apt-get build-dep -y -qq linux
apt-get install -y -qq --no-install-recommends \
    dpkg-dev quilt git lz4 gcc-multilib rsync

# ----------------------------------------------------------------------------
# 2. Fetch the Debian kernel source
# ----------------------------------------------------------------------------

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"
rm -rf linux-*/ linux_*.dsc linux_*.tar.*   # deterministic rebuilds
apt-get source linux
cd "${WORK_DIR}"/linux-*/

SRCVER="$(dpkg-parsechangelog -l debian/changelog -S Version)"
UPSTREAM="${SRCVER%%-*}"                    # 6.12.111
KERNSERIES="$(echo "${UPSTREAM}" | cut -d. -f1-2)"   # 6.12
echo ">>> source ${SRCVER}, kernel series ${KERNSERIES}, arch flavour aufs-amd64"

PATCH_DIR="${KERNEL_CONFIG}/${KERNSERIES}"
[ -d "${PATCH_DIR}" ] || {
    echo "no aufs kernel-patch set for series ${KERNSERIES} in ${KERNEL_CONFIG}" >&2
    exit 1
}

# ----------------------------------------------------------------------------
# 3. Import + apply the aufs patch set via quilt (fuzz allowed here, the
#    refreshed result is what debian/rules re-applies with --fuzz=0)
# ----------------------------------------------------------------------------

export QUILT_PATCHES="${PWD}/debian/patches" QUILT_PC=.pc
[ -f "${QUILT_PATCHES}/series" ] || {
    echo "cannot find ${QUILT_PATCHES}/series" >&2; exit 1;
}

# Copy the patches in (do NOT use `quilt import` — it inserts at the wrong
# position in the series file). Append at the end so aufs applies on top of
# Debian's own patch stack, in upstream order, then push one patch at a time
# and refresh it so the series is clean for debian/rules' --fuzz=0 pass.
for p in "${PATCH_DIR}"/*.patch; do
    name="$(basename "$p")"
    echo ">>> apply ${name}"
    cp "$p" "${QUILT_PATCHES}/${name}"
    echo "${name}" >> "${QUILT_PATCHES}/series"
    quilt push || {
        echo "!!! rejects while applying ${name}:" >&2
        find . -name '*.rej' -print >&2
        exit 1
    }
    quilt refresh
done

# ----------------------------------------------------------------------------
# 4. Packaging changes: single aufs-amd64 flavour, unsigned, changelog entry
#    Trixie (6.12) uses defines.toml; bullseye/bookworm use the INI layout.
# ----------------------------------------------------------------------------

if [ -f debian/config/defines.toml ]; then
    # allow a "+aufsN" suffix in the debian revision for every release regex
    python3 - <<'EOF'
import re
p = 'debian/config/defines.toml'
s = open(p).read()
s = re.sub(r"(revision_regex = '.*)'", r"\1(\\+aufs\\d+)?'", s)
open(p, 'w').write(s)
EOF
    grep -n 'revision_regex' debian/config/defines.toml
    cp "${PATCH_DIR}/amd64-defines.toml" debian/config/amd64/defines.toml
else
    # INI config: per-arch flavour list + full arch defines (carries the
    # aufs-amd64 description section and signed-code: false)
    cp "${PATCH_DIR}/amd64-none-defines" debian/config/amd64/none/defines
    cp "${PATCH_DIR}/amd64-defines" debian/config/amd64/defines
    # disable the rt featureset so it is not built as a second kernel;
    # bullseye already ships the section, bookworm needs it appended
    if grep -q '^\[featureset-rt_base\]' debian/config/defines; then
        sed -i '/^\[featureset-rt_base\]/,/^\[/ s/^enabled: true/enabled: false/' \
            debian/config/defines
    else
        printf '\n[featureset-rt_base]\nenabled: false\n' >> debian/config/defines
    fi
fi

# changelog: increment +aufsN if already present.
# NOTE: the changelog distribution must be the release codename itself
# (bullseye/bookworm/trixie); old gencontrol rejects "+aufsN" revisions
# for *-security distributions.
if echo "${SRCVER}" | grep -q '+aufs'; then
    n="$(echo "${SRCVER}" | sed -E 's/.*\+aufs([0-9]+).*/\1/')"
    NEWREV="$(echo "${SRCVER}" | sed -E 's/\+aufs[0-9]+//')+aufs$((n+1))"
else
    NEWREV="${SRCVER}+aufs1"
fi
DATE="$(date -R)"

cat > debian/changelog.new <<EOF
linux (${NEWREV}) ${DEB_FLAVOR}; urgency=medium

  * Apply upstream aufs standalone patches (base, mmap, standalone) so the
    kernel exports the symbols required to build aufs as an external
    (dkms) module
  * Add amd64 flavour "aufs-amd64"

 -- aufs-dkms-build CI <noreply@localhost>  ${DATE}

EOF
cat debian/changelog >> debian/changelog.new
mv debian/changelog.new debian/changelog
head -1 debian/changelog

# ----------------------------------------------------------------------------
# 5. Build
# ----------------------------------------------------------------------------

# First clean regenerates debian/control from the new defines.toml and
# exits non-zero intentionally; run it once up-front.
debian/rules clean || true

# -b (not -B): linux-headers-*-common is Architecture: all and is a hard
# dependency of the flavour headers package.
DEB_BUILD_OPTIONS="parallel=$(nproc) ${DEB_BUILD_OPTIONS:-}" \
    dpkg-buildpackage -us -uc -b

cd "${WORK_DIR}"
ls -la *.deb

# ----------------------------------------------------------------------------
# 6. Sanity gate: the flavour headers' Module.symvers must actually export
#    the symbols aufs needs (same check probe.sh performs at dkms time)
# ----------------------------------------------------------------------------

hdr="$(ls "${WORK_DIR}"/linux-headers-*-aufs-amd64_*_amd64.deb | head -1)"
tmpd="$(mktemp -d)"
dpkg-deb -x "${hdr}" "${tmpd}"
symvers="$(find "${tmpd}" -name Module.symvers | head -1)"

missing=0
for s in vfs_read vfs_write d_walk d_exchange do_truncate path_noexec \
         security_path_chmod security_path_rmdir security_path_symlink \
         security_file_permission; do
    awk -v s="${s}" '$2 == s && $4 ~ /^EXPORT_SYMBOL/ {f=1} END {exit !f}' \
        "${symvers}" || { echo "!!! missing export: ${s}" >&2; missing=1; }
done
[ "${missing}" -eq 0 ] || exit 1
echo ">>> all aufs exports verified in ${symvers}"
