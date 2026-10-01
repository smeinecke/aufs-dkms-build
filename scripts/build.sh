#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "${VERSION_TAG:-}" ]] || die "Parameter VERSION_TAG missing!"
[[ -n "${DEB_FLAVOR:-}" ]]  || die "Parameter DEB_FLAVOR missing!"

SCRIPTDIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
WORKDIR="${PWD}"

# debhelper compat level per Debian release
case "${DEB_FLAVOR}" in
    buster)                    DEBHELPER_COMPAT=12 ;;
    bullseye|bookworm|trixie)  DEBHELPER_COMPAT=13 ;;
    *) die "Unknown DEB_FLAVOR '${DEB_FLAVOR}'" ;;
esac

# dkms BUILD_EXCLUSIVE_KERNEL regex from the first two version components;
# double-escaped so it survives sed substitution into the dkms.conf template
IFS=. read -r KVER_MAJOR KVER_MINOR _ <<<"${VERSION_TAG}"
[[ "${KVER_MAJOR}" =~ ^[0-9]+$ && "${KVER_MINOR}" =~ ^[0-9]+$ ]] \
    || die "VERSION_TAG '${VERSION_TAG}' is not a kernel version"
KERNEL_REGEX="^${KVER_MAJOR}\\\\.${KVER_MINOR}.*"

# upstream split the standalone tree into per-major-version repositories
case "${KVER_MAJOR}" in
    4) AUFS_REPO="https://github.com/sfjro/aufs4-standalone" ;;
    *) AUFS_REPO="https://github.com/sfjro/aufs-standalone" ;;
esac
AUFS_BRANCH="aufs${VERSION_TAG}"

git config --global advice.detachedHead false

if [[ -d aufs-standalone && ! -d aufs-standalone/.git ]]; then
    rm -rf aufs-standalone
fi

if [[ -d aufs-standalone/.git ]]; then
    git -C aufs-standalone remote set-url origin "${AUFS_REPO}"
    git -C aufs-standalone fetch --depth 1 origin "${AUFS_BRANCH}"
    git -C aufs-standalone checkout -f FETCH_HEAD
else
    git clone --depth 1 --branch "${AUFS_BRANCH}" "${AUFS_REPO}" aufs-standalone
fi

cd "${WORKDIR}"
rm -rf aufs-dkms
mkdir -p aufs-dkms

# The dkms source tree is the whole standalone build system: the upstream
# top-level Makefile builds fs/aufs via kbuild using config.mk.
cp -a aufs-standalone/fs aufs-standalone/include aufs-standalone/Makefile \
    aufs-standalone/config.mk aufs-standalone/COPYING aufs-dkms/

# create original source tar file - just for dpkg-buildpackage compatibility
tar -czf "${WORKDIR}/aufs-dkms_${VERSION_TAG}.orig.tar.gz" -C aufs-dkms .

cd aufs-dkms

cp -r "${SCRIPTDIR}/debian" debian
echo "${DEBHELPER_COMPAT}" > debian/compat
sed -i "s|#KERNEL_REGEX#|${KERNEL_REGEX}|" debian/aufs-dkms.dkms
cat > debian/changelog <<EOF
aufs-dkms (${VERSION_TAG}-${DEB_FLAVOR}) ${DEB_FLAVOR}; urgency=medium

  * upstream release ${AUFS_BRANCH}

 -- Stefan Meinecke <meinecke@greensec.de>  $(date '+%a, %d %b %Y %H:%M:%S %z')
EOF

DEB_BUILD_OPTIONS="noautodbgsym nocheck nodocs" \
    dpkg-buildpackage -us -uc -b -j"$(nproc)"

cd "${WORKDIR}"
rm -f ./*-dbg*.deb
