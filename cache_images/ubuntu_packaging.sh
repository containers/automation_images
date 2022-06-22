#!/bin/bash

# This script is called from ubuntu_setup.sh and various Dockerfiles.
# It's not intended to be used outside of those contexts.  It assumes the lib.sh
# library has already been sourced, and that all "ground-up" package-related activity
# needs to be done, including repository setup and initial update.

set -e

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
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
# Overview: https://build.opensuse.org/project/show/devel:kubic:libcontainers:unstable
REPO_URL="https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/unstable/xUbuntu_$VERSION_ID/"
GPG_URL="https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/xUbuntu_$VERSION_ID/Release.key"

echo "deb $REPO_URL /" | ooe.sh $SUDO \
    tee /etc/apt/sources.list.d/devel:kubic:libcontainers:unstable:ci.list
curl --fail --silent --location --url "$GPG_URL" | \
    gpg --dearmor | \
    $SUDO tee /etc/apt/trusted.gpg.d/devel_kubic_libcontainers_unstable_ci.gpg &> /dev/null


# N/B: DO NOT install the bats package on Ubuntu VMs, it's broken.
# ref: (still open) https://bugs.launchpad.net/ubuntu/+source/bats/+bug/1882542
INSTALL_PACKAGES=(\
    apache2-utils
    apparmor
    apt-transport-https
    autoconf
    automake
    bash-completion
    bison
    btrfs-progs
    build-essential
    buildah
    bzip2
    ca-certificates
    catatonit
    conmon
    containernetworking-plugins
    containers-common
    criu
    crun
    dnsmasq
    e2fslibs-dev
    emacs-nox
    file
    fuse3
    git-daemon-run
    gcc
    gettext
    gnupg2
    go-md2man
    iproute2
    iptables
    jq
    libaio-dev
    libapparmor-dev
    libbtrfs-dev
    libcap-dev
    libcap2
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
    lsb-release
    lsof
    make
    netcat
    openssl
    parallel
    pkg-config
    podman
    podman-plugins
    protobuf-c-compiler
    protobuf-compiler
    python-is-python3
    python2
    python3-dateutil
    python3-dateutil
    python3-docker
    python3-pip
    python3-protobuf
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
    time
    unzip
    vim
    wget
    xz-utils
    zip
    zlib1g-dev
    zstd
)

# Necessary to update cache of newly added repos
lilto $SUDO apt-get -q -y update

if (($OS_RELEASE_VER>=2104)); then
    echo "Blocking golang-* package interfearance with kubik containers-common"
    $SUDO apt-mark hold golang-github-containers-common golang-github-containers-image
fi

echo "Installing general build/testing dependencies"
bigto $SUDO apt-get -q -y install "${INSTALL_PACKAGES[@]}"

# Buildah conformance testing needs to install packages from docker.io
# at runtime.  Setup the repo here, so it only affects downloaded
# (cached) packages and not updates/installs (above).  Installing packages
# cached in the image is preferable to reaching out to the repository
# at runtime.  It also has the desirable effect of preventing the
# possibility of package changes from one CI run to the next (or from
# one branch to the next).
DOWNLOAD_PACKAGES=(\
    containerd.io
    docker-ce
    docker-ce-cli
)

curl --fail --silent --location \
    --url  https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor | \
    $SUDO tee /etc/apt/trusted.gpg.d/docker_com.gpg &> /dev/null
echo "deb https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    ooe.sh $SUDO tee /etc/apt/sources.list.d/docker.list &> /dev/null

if ((CONTAINER==0)) && [[ ${#DOWNLOAD_PACKAGES[@]} -gt 0 ]]; then
    $SUDO apt-get clean  # no reason to keep previous downloads around
    # Needed to install .deb files + resolve dependencies
    lilto $SUDO apt-get -q -y update
    echo "Downloading packages for optional installation at runtime."
    $SUDO ln -s /var/cache/apt/archives "$PACKAGE_DOWNLOAD_DIR"
    bigto $SUDO apt-get -q -y install --download-only "${DOWNLOAD_PACKAGES[@]}"
fi

echo "Configuring Go environment"
# There are multiple (otherwise conflicting) versions of golang available
# on Ubuntu.  Being primarily localized by env. vars and defaults, dropping
# a symlink is the appropriate way to "install" a specific version system-wide.
#
# Add upstream golang for perf issues
curl -s -L https://golang.org/dl/go1.17.3.linux-amd64.tar.gz | \
    $SUDO tar xzf - -C /usr/local/
# Now linking to upstream golang until ubuntu performance issues are resolved
$SUDO ln -sf /usr/local/go/bin/* /usr/bin/

chmod +x $SCRIPT_DIRPATH/podman_tooling.sh
$SUDO bash $SCRIPT_DIRPATH/podman_tooling.sh
