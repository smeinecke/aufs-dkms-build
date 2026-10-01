# aufs-dkms-build
[![ci](https://github.com/smeinecke/aufs-dkms-build/actions/workflows/ci.yml/badge.svg)](https://github.com/smeinecke/aufs-dkms-build/actions/workflows/ci.yml)

Build aufs-dkms packages for Debian kernels.

Supported releases:

| Release | Codename | Kernel series | `VERSION_TAG` |
|---------|----------|---------------|---------------|
| 13      | trixie   | 6.12          | `6.12`        |
| 12      | bookworm | 6.1           | `6.1`         |
| 11      | bullseye (EOL, archive.debian.org) | 5.10 | `5.10` |
| 10      | buster (EOL, archive.debian.org) | 4.19 | `4.19` |

`VERSION_TAG` selects the `aufs<VERSION_TAG>` upstream branch (from
[sfjro/aufs-standalone](https://github.com/sfjro/aufs-standalone), or
aufs4-standalone for 4.x); the dkms module is restricted to the matching
kernel series (`BUILD_EXCLUSIVE_KERNEL`). For kernels where upstream ships
point-release branches (e.g. `6.12.29`), prefer the closest match to the
running kernel.

## Kernel requirements

aufs calls kernel-internal helpers (`vfs_read`, `d_walk`, `d_exchange`,
`security_path_*`, …) that are only available to modules when the kernel
was built with upstream's
[aufs-standalone patches](https://github.com/sfjro/aufs-standalone)
(`aufs6-base.patch` / `aufs6-standalone.patch`) applied.

* Debian 10 (buster, 4.19) is the last stock Debian kernel that still
  exports all required symbols — the module builds and loads there.
* Stock kernels of bullseye (5.10) and newer do **not** export them; the
  dkms build fails at install time with a message naming the missing
  symbols. Use these packages on a kernel built with the aufs export
  patches, or apply the patches to your kernel build.

The package also probes the target kernel headers at build time
(`probe.sh`) and adapts to distributor backports of upstream VFS API
changes (e.g. the `f_op->setfl`/`do_splice_from` removals Debian
backported into trixie's 6.12).

## Add Repo
```
apt-get install software-properties-common
apt-add-repository 'deb [arch=amd64] https://smeinecke.github.io/aufs-dkms-build/repo trixie main'
wget -O ~/dkms.key https://smeinecke.github.io/aufs-dkms-build/public.key
gpg --no-default-keyring --keyring ./dkms_keyring.gpg --import dkms.key
gpg --no-default-keyring --keyring ./dkms_keyring.gpg --export > ./dkms.gpg
mv ./dkms.gpg /etc/apt/trusted.gpg.d/
```

Replace `trixie` with your release codename (`bookworm`, `bullseye`, `buster`).

## Local build

Inside the corresponding build container (`docker/Dockerfile`, built with
`--build-arg FLAVOR=<codename>`):

```
DEB_FLAVOR=trixie VERSION_TAG=6.12 ./scripts/build.sh
```
