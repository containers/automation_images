#!/bin/bash

# This script is called from fedora_setup.sh and various Dockerfiles.
# It's not intended to be used outside of those contexts.  It assumes the lib.sh
# library has already been sourced, and that all "ground-up" package-related activity
# needs to be done, including repository setup and initial update.

set -e

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# packer and/or a --build-arg define this envar value uniformly
# for both VM and container image build workflows.
req_env_vars PACKER_BUILD_NAME

# Only enable updates-testing on all 'latest' Fedora images (except rawhide)
# as a matter of general policy.  Historically there have been many
# problems with non-uniform behavior when both supported Fedora releases
# receive container-related dependency updates at the same time.  Since
# the 'prior' release has the shortest support lifetime, keep it's behavior
# stable by only using released updates.
# shellcheck disable=SC2154
if [[ "$PACKER_BUILD_NAME" == "fedora" ]] && [[ ! "$PACKER_BUILD_NAME" =~ "prior" ]]; then
    warn "Enabling updates-testing repository for $PACKER_BUILD_NAME"
    lilto ooe.sh $SUDO dnf install -y 'dnf-command(config-manager)'
    lilto ooe.sh $SUDO dnf config-manager --set-enabled updates-testing
else
    warn "NOT enabling updates-testing repository for $PACKER_BUILD_NAME"
fi

msg "Updating/Installing repos and packages for $OS_REL_VER"

bigto ooe.sh $SUDO dnf update -y

INSTALL_PACKAGES=(\
    autoconf
    automake
    bash-completion
    bats
    bridge-utils
    btrfs-progs-devel
    buildah
    bzip2
    catatonit
    conmon
    containernetworking-plugins
    containers-common
    criu
    crun
    crun-wasm
    curl
    device-mapper-devel
    dnsmasq
    e2fsprogs-devel
    emacs-nox
    fakeroot
    file
    findutils
    fuse3
    fuse3-devel
    gcc
    git
    git-daemon
    glib2-devel
    glibc-devel
    glibc-langpack-en
    glibc-static
    gnupg
    go-md2man
    golang
    gpgme
    gpgme-devel
    grubby
    hostname
    httpd-tools
    iproute
    iptables
    jq
    krb5-workstation
    libassuan
    libassuan-devel
    libblkid-devel
    libcap-devel
    libffi-devel
    libgpg-error-devel
    libmsi1
    libnet
    libnet-devel
    libnl3-devel
    libseccomp
    libseccomp-devel
    libselinux-devel
    libtool
    libxml2-devel
    libxslt-devel
    lsof
    make
    man-db
    msitools
    nfs-utils
    nmap-ncat
    openssl
    openssl-devel
    ostree-devel
    pandoc
    parallel
    passt
    perl-Clone
    perl-FindBin
    pkgconfig
    podman
    pre-commit
    procps-ng
    protobuf
    protobuf-c
    protobuf-c-devel
    protobuf-devel
    redhat-rpm-config
    rpcbind
    rsync
    runc
    sed
    ShellCheck
    skopeo
    slirp4netns
    socat
    squashfs-tools
    tar
    time
    unzip
    vim
    wget
    which
    xz
    zip
    zlib-devel
    zstd
)

# Rawhide images don't need these packages
if [[ "$PACKER_BUILD_NAME" =~ fedora ]]; then
    INSTALL_PACKAGES+=( \
        docker-compose
        python-pip-wheel
        python-setuptools-wheel
        python-toml
        python-wheel-wheel
        python2
        python3-PyYAML
        python3-coverage
        python3-dateutil
        python3-devel
        python3-docker
        python3-fixtures
        python3-libselinux
        python3-libsemanage
        python3-libvirt
        python3-pip
        python3-psutil
        python3-pylint
        python3-pyxdg
        python3-requests
        python3-requests-mock
    )
fi

# When installing during a container-build, having this present
# will seriously screw up future dnf operations in very non-obvious ways.
# bpftrace is only needed on the host as containers cannot run ebpf
# programs anyway and it is very big so we should not bloat the container
# images unnecessarily.
if ! ((CONTAINER)); then
    INSTALL_PACKAGES+=( \
        bpftrace
        container-selinux
        libguestfs-tools
        selinux-policy-devel
        policycoreutils
    )
fi


# Download these package files, but don't install them; Any tests
# wishing to, may install them using their native tools at runtime.
DOWNLOAD_PACKAGES=(\
    parallel
    podman-docker
    python3-devel
    python3-pip
    python3-pytest
    python3-virtualenv
)

msg "Installing general build/test dependencies"
bigto $SUDO dnf install -y "${INSTALL_PACKAGES[@]}"

# 2024-10-31 fixes CI flake
timebomb 20241111 "pasta 20241030 still in testing for all arches"
arch=$(uname -m)
n=passt
v=0%5E20241030.gee7d0b6
r=1.fc$OS_RELEASE_VER
bigto $SUDO dnf install -y  \
      https://kojipkgs.fedoraproject.org/packages/$n/$v/$r/$arch/$n-$v-$r.$arch.rpm \
      https://kojipkgs.fedoraproject.org/packages/$n/$v/$r/noarch/$n-selinux-$v-$r.noarch.rpm

# 2024-10-31 FIXME! 1.18.1 is buggy, but .2 does not yet have koji builds
timebomb 20241111 "needed to test pod checkpoint/restore"
n=crun
v=1.18.1
bigto $SUDO dnf install -y  \
      https://kojipkgs.fedoraproject.org/packages/$n/$v/$r/$arch/$n-$v-$r.$arch.rpm


msg "Downloading packages for optional installation at runtime, as needed."
$SUDO mkdir -p "$PACKAGE_DOWNLOAD_DIR"
cd "$PACKAGE_DOWNLOAD_DIR"
lilto ooe.sh $SUDO dnf install -y 'dnf-command(download)'
lilto $SUDO dnf download -y --resolve "${DOWNLOAD_PACKAGES[@]}"
# Also cache the current/latest version of minikube
# for use in some specialized testing.
# Ref: https://minikube.sigs.k8s.io/docs/start/
$SUDO curl --fail --silent --location -O \
    https://storage.googleapis.com/minikube/releases/latest/minikube-latest.x86_64.rpm
cd -

# Occasionally following an install, there are more updates available.
# This may be due to activation of suggested/recommended dependency resolution.
lilto $SUDO dnf update -y
