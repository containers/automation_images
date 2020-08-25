#!/bin/bash

# This script is called from ubuntu_setup.sh and various Dockerfiles.
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

lilto ooe.sh $SUDO apt-get -qq -y update
bigto ooe.sh $SUDO apt-get -qq -y upgrade

echo "Configuring additional package repositories"
lilto ooe.sh $SUDO add-apt-repository --yes ppa:criu/ppa
VERSION_ID=$(source /etc/os-release; echo $VERSION_ID)
echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_$VERSION_ID/ /" \
    | ooe.sh $SUDO tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
ooe.sh curl -L -o /tmp/Release.key "https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/xUbuntu_${VERSION_ID}/Release.key"
ooe.sh $SUDO apt-key add - < /tmp/Release.key

INSTALL_PACKAGES=(\
    apache2-utils
    apparmor
    aufs-tools
    autoconf
    automake
    bash-completion
    bats
    bison
    btrfs-progs
    build-essential
    buildah
    bzip2
    conmon
    containernetworking-plugins
    containers-common
    coreutils
    cri-o-runc
    criu
    curl
    dnsmasq
    e2fslibs-dev
    emacs-nox
    file
    fuse3
    gawk
    gcc
    gettext
    git
    go-md2man
    golang-1.14
    iproute2
    iptables
    jq
    libaio-dev
    libapparmor-dev
    libbtrfs-dev
    libcap-dev
    libdevmapper-dev
    libdevmapper1.02.1
    libfuse-dev
    libfuse2
    libfuse3-dev
    libglib2.0-dev
    libgpgme11-dev
    liblzma-dev
    libnet1
    libnet1-dev
    libnl-3-dev
    libprotobuf-c-dev
    libprotobuf-dev
    libseccomp-dev
    libseccomp2
    libselinux-dev
    libsystemd-dev
    libtool
    libudev-dev
    libvarlink
    lsof
    make
    netcat
    openssl
    pkg-config
    podman
    protobuf-c-compiler
    protobuf-compiler
    python-dateutil
    python-protobuf
    python2
    python3-dateutil
    python3-pip
    python3-psutil
    python3-pytoml
    python3-requests
    python3-setuptools
    rsync
    runc
    scons
    skopeo
    slirp4netns
    socat
    sudo
    unzip
    vim
    wget
    xz-utils
    zip
    zlib1g-dev
)
DOWNLOAD_PACKAGES=(\
    "cri-o-$(get_kubernetes_version)"
    cri-tools
    parallel
)

# These aren't resolvable on Ubuntu 20
if [[ "$OS_RELEASE_VER" -le 19 ]]; then
    INSTALL_PACKAGES+=(\
        python-future
        python-minimal
        yum-utils
    )
else
    INSTALL_PACKAGES+=(\
        python-is-python3
    )
fi

echo "Installing general build/testing dependencies"
# Necessary to update cache of newly added repos
lilto ooe.sh $SUDO apt-get -qq -y update
bigto ooe.sh $SUDO apt-get -qq -y install "${INSTALL_PACKAGES[@]}"

if [[ ${#DOWNLOAD_PACKAGES[@]} -gt 0 ]]; then
    echo "Downloading packages for optional installation at runtime, as needed."
    $SUDO ln -s /var/cache/apt/archives "$PACKAGE_DOWNLOAD_DIR"
    bigto ooe.sh $SUDO apt-get -qq -y install --download-only "${DOWNLOAD_PACKAGES[@]}"
fi

echo "Configuring Go environment"
# There are multiple (otherwise conflicting) versions of golang available
# on Ubuntu.  Being primarily localized by env. vars and defaults, dropping
# a symlink is the appropriate way to "install" a specific version system-wide.
$SUDO ln -sf /usr/lib/go-1.14/bin/go /usr/bin/go

mkdir -p /var/tmp/go
export GOPATH=/var/tmp/go
eval $(go env | tee /dev/stderr)
export PATH="$GOPATH/bin:$PATH"

# shellcheck source=./podman_tooling.sh
source $SCRIPT_DIRPATH/podman_tooling.sh
