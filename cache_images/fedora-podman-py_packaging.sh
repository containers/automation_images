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

# shellcheck disable=SC2154
warn "Enabling updates-testing repository for $PACKER_BUILD_NAME"
lilto ooe.sh $SUDO dnf install -y 'dnf-command(config-manager)'
lilto ooe.sh $SUDO dnf config-manager setopt updates-testing.enabled=1

msg "Updating/Installing repos and packages for $OS_REL_VER"

bigto ooe.sh $SUDO dnf update -y

INSTALL_PACKAGES=(\
    bash-completion
    bridge-utils
    buildah
    bzip2
    curl
    findutils
    fuse3
    gcc
    git
    git-daemon
    glib2-devel
    glibc-devel
    hostname
    httpd-tools
    iproute
    iptables
    jq
    libtool
    lsof
    make
    nmap-ncat
    openssl
    openssl-devel
    pkgconfig
    podman
    policycoreutils
    protobuf
    protobuf-devel
    python-pip-wheel
    python-setuptools-wheel
    python-toml
    python-wheel-wheel
    python3-PyYAML
    python3-coverage
    python3-dateutil
    python3-docker
    python3-fixtures
    python3-libselinux
    python3-libsemanage
    python3-libvirt
    python3-pip
    python3-psutil
    python3-pylint
    python3-pytest
    python3-requests
    python3-requests-mock
    python3-virtualenv
    python3.6
    python3.9
    python3.10
    python3.11
    python3.12
    redhat-rpm-config
    rsync
    sed
    skopeo
    socat
    tar
    time
    tox
    unzip
    vim
    wget
    xz
    zip
    zstd
)

echo "Installing general build/test dependencies"
bigto $SUDO dnf install -y "${INSTALL_PACKAGES[@]}"

# It was observed in F33, dnf install doesn't always get you the latest/greatest
lilto $SUDO dnf update -y
