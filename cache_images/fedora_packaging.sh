#!/bin/bash

# This script is called from fedora_setup.sh and various Dockerfiles.
# It's not intended to be used outside of those contexts.  It assumes the lib.sh
# library has already been sourced, and that all "ground-up" package-related activity
# needs to be done, including repository setup and initial update.

set -e

SCRIPT_FILEPATH=$(realpath "$0")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

echo "Updating/Installing repos and packages for $OS_REL_VER"

# Set this to 1 to NOT enable updates-testing repository
ENABLE_UPDATES_TESTING=${ENABLE_UPDATES_TESTING:-1}
if ((ENABLE_UPDATES_TESTING)); then
    warn "Enabling updates-testing repository for $OS_REL_VER"
    lilto ooe.sh $SUDO dnf install -y 'dnf-command(config-manager)'
    lilto ooe.sh $SUDO dnf config-manager --set-enabled updates-testing
else
    warn "NOT enabling updates-testing repository for $OS_REL_VER"
fi

bigto ooe.sh $SUDO dnf update -y

# Fedora, as of 31, uses cgroups v2 by default. runc does not support
# cgroups v2, only crun does. (As of 2020-07-30 runc support is
# forthcoming but not even close to ready yet). To ensure a reliable
# runtime environment, force-remove runc if it is present.
# However, because a few other repos. which use these images still need
# it, ensure the runc package is cached in $PACKAGE_DOWNLOAD_DIR so
# it may be swap it in when required.
REMOVE_PACKAGES=(runc)

INSTALL_PACKAGES=(\
    autoconf
    automake
    bash-completion
    bats
    bridge-utils
    btrfs-progs-devel
    buildah
    bzip2
    conmon
    containernetworking-plugins
    containers-common
    criu
    crun
    curl
    device-mapper-devel
    dnsmasq
    e2fsprogs-devel
    emacs-nox
    file
    findutils
    fuse3
    fuse3-devel
    gcc
    git
    glib2-devel
    glibc-devel
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
    libvarlink-util
    libxml2-devel
    libxslt-devel
    lsof
    make
    mlocate
    msitools
    nfs-utils
    nmap-ncat
    openssl
    openssl-devel
    ostree-devel
    pandoc
    pkgconfig
    podman
    procps-ng
    protobuf
    protobuf-c
    protobuf-c-devel
    protobuf-devel
    python2
    python3-PyYAML
    python3-dateutil
    python3-libselinux
    python3-libsemanage
    python3-libvirt
    python3-psutil
    python3-pytoml
    python3-requests
    redhat-rpm-config
    rpcbind
    rsync
    sed
    skopeo
    skopeo-containers
    slirp4netns
    socat
    tar
    unzip
    vim
    wget
    which
    xz
    zip
    zlib-devel
)

# When installing during a container-build, having this present
# will seriously screw up future dnf operations in very non-obvious ways.
if ! ((CONTAINER)); then
    INSTALL_PACKAGES+=( \
        container-selinux
        libguestfs-tools
        selinux-policy-devel
        policycoreutils
    )
else
    EXARG="--exclude=selinux*"
fi


DOWNLOAD_PACKAGES=(\
    "cri-o-$(get_kubernetes_version)*"
    cri-tools
    "kubernetes-$(get_kubernetes_version)*"
    runc
    oci-umount
    parallel
)

echo "Installing general build/test dependencies"
bigto ooe.sh $SUDO dnf install -y $EXARG "${INSTALL_PACKAGES[@]}"

if [[ ${#REMOVE_PACKAGES[@]} -gt 0 ]]; then
    lilto ooe.sh $SUDO dnf erase -y "${REMOVE_PACKAGES[@]}"
fi

if [[ ${#DOWNLOAD_PACKAGES[@]} -gt 0 ]]; then
    echo "Downloading packages for optional installation at runtime, as needed."
    # Required for cri-o
    ooe.sh $SUDO dnf -y module enable cri-o:$(get_kubernetes_version)
    $SUDO mkdir -p "$PACKAGE_DOWNLOAD_DIR"
    cd "$PACKAGE_DOWNLOAD_DIR"
    lilto ooe.sh $SUDO dnf download -y --resolve "${DOWNLOAD_PACKAGES[@]}"
fi

echo "Configuring Go environment"
export GOPATH=/var/tmp/go
mkdir -p "$GOPATH"
eval $(go env | tee /dev/stderr)
export PATH="$GOPATH/bin:$PATH"
# shellcheck source=./podman_tooling.sh
source $SCRIPT_DIRPATH/podman_tooling.sh
