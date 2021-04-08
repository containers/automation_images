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


# Useful version of criu is only available from launchpad repo
if [[ "$OS_RELEASE_VER" -le 2004 ]]; then
    lilto ooe.sh $SUDO add-apt-repository --yes ppa:criu/ppa
fi

# The OpenSuse Open Build System must be utilized to obtain newer
# development versions of podman/buildah/skopeo & dependencies,
# in order to support upstream (i.e. bleeding-edge) development and
# automated testing.  These packages are not otherwise intended for
# end-user consumption.
VERSION_ID=$(source /etc/os-release; echo $VERSION_ID)
REPO_URL="https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/testing/xUbuntu_$VERSION_ID/"
GPG_URL="https://download.opensuse.org/repositories/devel:kubic:libcontainers:testing/xUbuntu_$VERSION_ID/Release.key"

echo "deb $REPO_URL /" | ooe.sh $SUDO \
    tee /etc/apt/sources.list.d/devel:kubic:libcontainers:testing:ci.list
curl --fail --silent --location --url "$GPG_URL" | \
    gpg --dearmor | \
    $SUDO tee /etc/apt/trusted.gpg.d/devel_kubic_libcontainers_testing_ci.gpg &> /dev/null


# Removed golang-1.14 from install packages due to known
# performance reason.  Reinstall when ubuntu has 1.16.

INSTALL_PACKAGES=(\
    apache2-utils
    apparmor
    aufs-tools
    autoconf
    automake
    bash-completion
    bison
    btrfs-progs
    build-essential
    buildah
    bzip2
    conmon
    containernetworking-plugins
    coreutils
    cri-o-runc
    criu
    crun
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
    gnupg2
    go-md2man
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
    libseccomp2
    libseccomp-dev
    libselinux-dev
    libsystemd-dev
    libtool
    libudev-dev
    lsof
    make
    netcat
    openssl
    parallel
    pkg-config
    podman
    protobuf-c-compiler
    protobuf-compiler
    python2
    python3-dateutil
    python3-docker
    python3-pip
    python3-psutil
    python3-pytoml
    python3-requests
    python3-setuptools
    rsync
    scons
    skopeo
    slirp4netns
    socat
    sudo
    time
    unzip
    vim
    wget
    xz-utils
    zip
    zlib1g-dev
    zstd
)
# Download these package files, but don't install them; Any tests
# wishing to, may install them using their native tools at runtime.
DOWNLOAD_PACKAGES=(\
    parallel
)

# These aren't resolvable on Ubuntu 20
if [[ "$OS_RELEASE_VER" -le 2004 ]]; then
    INSTALL_PACKAGES+=(\
        python-dateutil
        python-is-python3
        python-protobuf
    )
else  # e.g. 20.10 and later
    INSTALL_PACKAGES+=(\
        libcap2
        podman-plugins
        python-is-python3
        python3-dateutil
        python3-protobuf
    )

fi

echo "Installing general build/testing dependencies"
# Necessary to update cache of newly added repos
lilto $SUDO apt-get -q -y update
bigto $SUDO apt-get -q -y install "${INSTALL_PACKAGES[@]}"

if [[ ${#DOWNLOAD_PACKAGES[@]} -gt 0 ]]; then
    echo "Downloading packages for optional installation at runtime, as needed."
    $SUDO ln -s /var/cache/apt/archives "$PACKAGE_DOWNLOAD_DIR"
    bigto $SUDO apt-get -q -y install --download-only "${DOWNLOAD_PACKAGES[@]}"
fi

echo "Configuring Go environment"
# There are multiple (otherwise conflicting) versions of golang available
# on Ubuntu.  Being primarily localized by env. vars and defaults, dropping
# a symlink is the appropriate way to "install" a specific version system-wide.
#
# Add upstream golang for perf issues
curl -s -L https://golang.org/dl/go1.15.11.linux-amd64.tar.gz | $SUDO tar xzf - -C /usr/local/
# Now linking to upstream golang until ubuntu performance issues are resolved
$SUDO ln -sf /usr/local/go/bin/go /usr/bin/go

export GOPATH=/var/tmp/go
mkdir -p "$GOPATH"
eval $(go env | tee /dev/stderr)
export PATH="$GOPATH/bin:$PATH"

# shellcheck source=./podman_tooling.sh
source $SCRIPT_DIRPATH/podman_tooling.sh
