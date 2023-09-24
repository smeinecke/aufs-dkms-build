#!/bin/bash
set -e

if [[ -z "${VERSION_TAG}" ]]; then
    echo "Parameter VERSION_TAG missing!"
fi

if [[ -z "${DEB_FLAVOR}" ]]; then
    echo "Parameter DEB_FLAVOR missing!"
fi

SCRIPT=$(readlink -f "$0")
SCRIPTDIR=$(dirname "${SCRIPT}")
WORKDIR="${PWD}"

git config --global advice.detachedHead false

# Display tools version
cmake --version | head -n 1

# Enable ccache
export PATH="/usr/lib/ccache:${PATH}"
export CCACHE_DIR="${WORKDIR}/cache/ccache"

# Checkout handbreak
cd "${WORKDIR}"
mkdir -p aufs-dkms

if [[ -d aufs-standalone ]]; then
  cd aufs-standalone
  git clean -xdf
  git fetch -t
  git checkout master
  git pull --ff-only
  cd ..
else
  git clone --branch master https://github.com/sfjro/aufs-standalone
fi

cd aufs-standalone
echo "Checkout: ${VERSION_TAG}"
git checkout "aufs${VERSION_TAG}"

cd "${WORKDIR}"
cp -va "${WORKDIR}/aufs-standalone/fs/aufs" "${WORKDIR}/aufs-dkms/src"
# create original source tar file - just for dpkg-buildpackage compatibility
tar -cjf "${WORKDIR}/aufs-dkms_${VERSION_TAG}.orig.tar.bz2" -C "${WORKDIR}/aufs-dkms" .

cd "${WORKDIR}/aufs-dkms"

cp -vr "${SCRIPTDIR}/debian-${DEB_FLAVOR}" debian
(
  echo "aufs-dkms (${VERSION_TAG}-${DEB_FLAVOR}) unstable; urgency=high"
  echo ""
  echo "  * upstream release"
  echo ""
  echo " -- Stefan Meinecke <meinecke@greensec.de>  $(date '+%a, %d %b %Y %H:%M:%S %z')"
  echo ""
) > debian/changelog

if [ -d "${WORKDIR}/patches.$DEB_FLAVOR" ]; then
  cp -va "${WORKDIR}/patches.$DEB_FLAVOR" debian/
fi

DEB_BUILD_OPTIONS="noautodbgsym nocheck nodocs" dpkg-buildpackage -j$(nproc) -d -us -b
cd ..
rm -vf *-dbg*.deb
