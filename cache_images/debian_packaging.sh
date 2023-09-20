#!/bin/bash

# This script is called from debian_setup.sh and various Dockerfiles.
# It's not intended to be used outside of those contexts.  It assumes the lib.sh
# library has already been sourced, and that all "ground-up" package-related activity
# needs to be done, including repository setup and initial update.

set -e

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

msg "Updating/Installing repos and packages for $OS_REL_VER"
lilto ooe.sh $SUDO apt-get -qq -y update
bigto ooe.sh $SUDO apt-get -qq -y upgrade

INSTALL_PACKAGES=(\
    apache2-utils
    apparmor
    apt-transport-https
    autoconf
    automake
    bash-completion
    bats
    bison
    btrfs-progs
    build-essential
    buildah
    bzip2
    ca-certificates
    catatonit
    conmon
    containernetworking-plugins
    criu
    crun
    dnsmasq
    e2fslibs-dev
    file
    fuse3
    fuse-overlayfs
    gcc
    gettext
    git-daemon-run
    gnupg2
    go-md2man
    golang
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
    libostree-dev
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
    ncat
    openssl
    parallel
    passt
    pkg-config
    podman
    protobuf-c-compiler
    protobuf-compiler
    python-is-python3
    python3-dateutil
    python3-dateutil
    python3-docker
    python3-pip
    python3-protobuf
    python3-psutil
    python3-toml
    python3-tomli
    python3-requests
    python3-setuptools
    rsync
    runc
    scons
    skopeo
    slirp4netns
    socat
    systemd-container
    sudo
    time
    unzip
    vim
    wget
    xfsprogs
    xz-utils
    zip
    zlib1g-dev
    zstd
)

msg "Installing general build/testing dependencies"
bigto $SUDO apt-get -q -y install "${INSTALL_PACKAGES[@]}"

# The nc installed by default is missing many required options
$SUDO update-alternatives --set nc /usr/bin/ncat

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
    --url  https://download.docker.com/linux/debian/gpg | \
    gpg --dearmor | \
    $SUDO tee /etc/apt/trusted.gpg.d/docker_com.gpg &> /dev/null

# Buildah CI does conformance testing vs the most recent Docker version.
# FIXME: As of 7-2023, there is no 'trixie' dist for docker. Fix the next lines once that changes.
#docker_debian_release=$(source /etc/os-release; echo "$VERSION_CODENAME")
docker_debian_release="bookworm"

echo "deb https://download.docker.com/linux/debian $docker_debian_release stable" | \
    ooe.sh $SUDO tee /etc/apt/sources.list.d/docker.list &> /dev/null

if ((CONTAINER==0)) && [[ ${#DOWNLOAD_PACKAGES[@]} -gt 0 ]]; then
    $SUDO apt-get clean  # no reason to keep previous downloads around
    # Needed to install .deb files + resolve dependencies
    lilto $SUDO apt-get -qq -y update
    echo "Downloading packages for optional installation at runtime."
    $SUDO ln -s /var/cache/apt/archives "$PACKAGE_DOWNLOAD_DIR"
    bigto $SUDO apt-get -q -y install --download-only "${DOWNLOAD_PACKAGES[@]}"
fi
