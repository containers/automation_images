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

msg "Updating/Installing repos and packages for $OS_REL_VER"

bigto ooe.sh $SUDO dnf update -y

INSTALL_PACKAGES=(\
    bats
    bridge-utils
    bzip2
    cargo
    clippy
    curl
    dbus-daemon
    findutils
    firewalld
    git
    gzip
    hostname
    iproute
    iptables
    iputils
    jq
    kernel-modules
    make
    nftables
    nmap-ncat
    openssl
    openssl-devel
    policycoreutils
    redhat-rpm-config
    rpm-build
    rsync
    rust
    rustfmt
    sed
    tar
    time
    xz
    zip
)

# TODO: Remove this when all CI should test with Netavark/Aardvark by default
EXARG="--exclude=netavark --exclude=aardvark-dns"

msg "Installing general build/test dependencies"
bigto $SUDO dnf install -y $EXARG "${INSTALL_PACKAGES[@]}"

msg "Installing netavark-specific toolchain dependencies"
export CARGO_HOME="/var/cache/cargo"  # must match .cirrus.yml in netavark repo
$SUDO env CARGO_HOME=$CARGO_HOME cargo install mandown sccache

# It was observed in F33, dnf install doesn't always get you the latest/greatest
lilto $SUDO dnf update -y
