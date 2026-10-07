# aufs-dkms-build
[![ci](https://github.com/smeinecke/aufs-dkms-build/actions/workflows/ci.yml/badge.svg)](https://github.com/smeinecke/aufs-dkms-build/actions/workflows/ci.yml)

Build aufs-dkms packages for Debian kernels.

Supported releases:

| Release | Codename | Kernel series | `VERSION_TAG` |
|---------|----------|---------------|---------------|
| 13      | trixie   | 6.12          | `6.12`        |
| 12      | bookworm | 6.1           | `6.1`         |
| 11      | bullseye (EOL, archive.debian.org) | 5.10 | `5.10.140` |
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
  symbols. Use the aufs-enabled kernel packages below, or apply the
  patches to your own kernel build.

The package also probes the target kernel headers at build time
(`probe.sh`) and adapts to distributor backports of upstream VFS API
changes (e.g. the `f_op->setfl`/`do_splice_from` removals Debian
backported into trixie's 6.12).

## aufs-enabled kernel packages

For releases newer than buster this repository builds patched Debian
kernel packages in addition to `aufs-dkms`: an extra `aufs-amd64` flavour
of the regular Debian kernel, with `aufs{4,5,6}-{base,mmap,standalone}.patch`
applied so the required symbols are exported. aufs itself stays in the
dkms package — nothing else about the kernel changes.

Packages are named `linux-image-<kver>-aufs-amd64` and coexist with the
stock kernel (separate `/lib/modules` tree, separate GRUB entries), so the
stock kernel remains available as a fallback.

```
# after adding the apt repo below:
apt-get install linux-image-aufs-amd64 linux-headers-aufs-amd64 aufs-dkms
reboot   # and select the -aufs-amd64 kernel
```

Or download the `linux-image`/`linux-headers`/`linux-kbuild` debs from the
latest `kernel-<codename>-*` release on GitHub and `apt-get install ./*.deb`.

Notes:

* amd64 only. The packages are **unsigned**: disable Secure Boot or set up
  your own MOK signing.
* The flavour tracks Debian's kernel ABI; a Debian point release or
  security update produces a new `+aufsN` build automatically (weekly CI).
* trixie: the `linux-image` deb grew past GitHub's 100MB per-file git
  limit, so the apt repo carries only headers/kbuild. Get the matching
  `linux-image-*-aufs-amd64` deb from the latest `kernel-trixie-*` (or
  `6.12.29`) release and `apt-get install ./linux-image-*.deb` - the
  headers/kbuild deps still resolve from the repo.
* `scripts/build-kernel.sh <codename>` builds these packages locally;
  per-series patch sets live in `scripts/kernel/<series>/`.

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
