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
    automake
    bats
    bind-utils
    bridge-utils
    btrfs-progs-devel
    bzip2
    curl
    dbus-daemon
    findutils
    firewalld
    gcc
    gcc-c++
    git
    golang
    gpgme-devel
    gzip
    hostname
    iproute
    iptables
    iputils
    jq
    kernel-devel
    kernel-modules
    libassuan-devel
    libseccomp-devel
    make
    nftables
    nmap-ncat
    openssl
    openssl-devel
    podman
    policycoreutils
	protobuf-compiler
    rsync
    sed
    slirp4netns
    systemd-devel
    tar
    time
    xz
    zip
)

EXARG="--exclude=cargo --exclude=rust"

msg "Installing general build/test dependencies"
bigto $SUDO dnf install -y $EXARG "${INSTALL_PACKAGES[@]}"

# It was observed in F33, dnf install doesn't always get you the latest/greatest.
lilto $SUDO dnf update -y $EXARG

msg "Initializing upstream rust environment."
export CARGO_HOME="/var/cache/cargo"  # must match .cirrus.yml in netavark repo
$SUDO mkdir -p $CARGO_HOME
# CI Runtime takes care of recovering $CARGO_HOME/env
curl https://sh.rustup.rs -sSf | $SUDO env CARGO_HOME=$CARGO_HOME sh -s -- -y

# Downstream users of this image are specifically testing netavark & aardvark-dns
# code changes.  We want to start with using the RPMs because they deal with any
# dependency issues.  However, we don't actually want the binaries present on
# the system, because:
# 1) They will be compiled from source at runtime
# 2) The file locations may change
# 3) We never want testing ambiguity WRT which binary is under test.
msg "Clobbering netavark & aardvark RPM files"
remove_netavark_aardvark_files
