#!/bin/bash
# In-guest integration test for the aufs-dkms package.
# Runs as the 'debian' user (passwordless sudo) inside a Debian cloud VM.
# Expects the aufs-dkms_*_all.deb file in the home directory.
set -euxo pipefail

# EOL releases only resolve via archive.debian.org
case "$(. /etc/os-release && echo "${VERSION_CODENAME}")" in
    buster)
        printf '%s\n' \
            'deb http://archive.debian.org/debian buster main' \
            'deb http://archive.debian.org/debian buster-updates main' \
            'deb http://archive.debian.org/debian-security buster/updates main' \
            | sudo tee /etc/apt/sources.list >/dev/null
        echo 'Acquire::Check-Valid-Until "false";' \
            | sudo tee /etc/apt/apt.conf.d/99_archive >/dev/null
        ;;
esac

sudo apt-get update -qq

# On an aufs-flavoured kernel (installed from our own packages) the headers
# are not in the Debian archive - they were installed alongside the kernel.
if [[ "$(uname -r)" == *aufs* ]]; then
    test -d "/lib/modules/$(uname -r)/build" || {
        echo "headers for $(uname -r) missing" >&2; exit 1;
    }
    headers_pkg=""
else
    headers_pkg="linux-headers-$(uname -r)"
fi
sudo apt-get install -y -qq --no-install-recommends \
    ${headers_pkg:+"${headers_pkg}"} dkms build-essential kmod

sudo dpkg -i aufs-dkms_*_all.deb

# the module must actually load on the running kernel
sudo modprobe aufs
lsmod | grep -q '^aufs '

# functional check: union mount + write-through + copy-up
work="$(mktemp -d)"
mkdir -p "${work}/rw" "${work}/ro" "${work}/mnt"
echo ro-branch-content > "${work}/ro/lower.txt"
echo rw-branch-content > "${work}/rw/upper.txt"

sudo mount -t aufs -o "br=${work}/rw=rw:${work}/ro=ro" none "${work}/mnt"
mount | grep -q ' type aufs '
grep -q ro-branch-content "${work}/mnt/lower.txt"
grep -q rw-branch-content "${work}/mnt/upper.txt"

echo union-write > "${work}/mnt/newfile.txt"
grep -q union-write "${work}/rw/newfile.txt"
test ! -e "${work}/ro/newfile.txt"

echo appended >> "${work}/mnt/lower.txt"
grep -q appended "${work}/rw/lower.txt"
! grep -q appended "${work}/ro/lower.txt"

sudo umount "${work}/mnt"
echo "integration test passed"
