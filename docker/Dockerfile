ARG FLAVOR=bookworm
FROM debian:${FLAVOR}-slim

ARG FLAVOR
ARG DEBIAN_FRONTEND=noninteractive

ADD assets/dpkg_nodoc /etc/dpkg/dpkg.cfg.d/90_nodoc
ADD assets/dpkg_nolocale /etc/dpkg/dpkg.cfg.d/90_nolocale
ADD assets/apt_nocache /etc/apt/apt.conf.d/90_nocache
ADD assets/apt_mindeps /etc/apt/apt.conf.d/90_mindeps

# EOL releases only exist on archive.debian.org with expired Release files
RUN	set -eux; \
    if [ "${FLAVOR}" = "buster" ]; then \
        printf '%s\n' \
            'deb http://archive.debian.org/debian buster main' \
            'deb http://archive.debian.org/debian buster-updates main' \
            'deb http://archive.debian.org/debian-security buster/updates main' \
            > /etc/apt/sources.list; \
    elif [ "${FLAVOR}" = "bullseye" ]; then \
        printf '%s\n' \
            'deb http://archive.debian.org/debian bullseye main' \
            'deb http://archive.debian.org/debian bullseye-updates main' \
            'deb http://snapshot.debian.org/archive/debian-security/20260901T000000Z bullseye-security main' \
            > /etc/apt/sources.list; \
    fi; \
    if [ "${FLAVOR}" = "buster" ] || [ "${FLAVOR}" = "bullseye" ]; then \
        echo 'Acquire::Check-Valid-Until "false";' \
            > /etc/apt/apt.conf.d/99_archive; \
    fi

# build dependencies
RUN	set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential ca-certificates debhelper dkms fakeroot git quilt; \
    if apt-cache show dh-dkms >/dev/null 2>&1; then \
        apt-get install -y --no-install-recommends dh-dkms; \
    fi; \
    rm -rf /var/lib/apt/lists/*; \
    rm -rf /tmp/* /var/tmp/* /var/log/*
