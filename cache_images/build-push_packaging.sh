#!/bin/bash

# This script is called from build-push_setup.sh by packer.  It's not intended
# to be used outside of those contexts.  It assumes the lib.sh library has
# already been sourced, and that all "ground-up" package-related activity
# needs to be done, including repository setup and initial update.

set -e

SCRIPT_FILEPATH=$(realpath "$0")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# packer and/or a --build-arg define this envar value uniformly
# for both VM and container image build workflows.
req_env_vars PACKER_BUILD_NAME

msg "Updating/Installing repos and packages for $OS_REL_VER"

bigto ooe.sh $SUDO dnf update -y

INSTALL_PACKAGES=(\
    buildah
    git
    jq
    podman
    python3-pip
    qemu-user-static
    skopeo
)

echo "Installing general build/test dependencies"
bigto $SUDO dnf install -y "${INSTALL_PACKAGES[@]}"

# It was observed in F33, dnf install doesn't always get you the latest/greatest
lilto $SUDO dnf update -y

# Re-install with the 'build-push' component
install_automation_tooling build-push

# Install main scripts into directory on $PATH
cd $REPO_DIRPATH/build-push
set -x
# Do not auto-update to allow testing inside a PR
$SUDO env BUILDPUSHAUTOUPDATED=1 bash ./.install.sh

# Install wait-for-copr
$SUDO pip3 install git+https://github.com/packit/wait-for-copr.git@main
