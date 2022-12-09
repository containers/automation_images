#!/bin/bash

# This script is executed from *_packaging.sh script to install common/shared
# tooling from the containers/podman repository.  It expects
# a go 1.16+ environment has already been set up, and should be called
# as root or through sudo.  The script should not be used for any other
# purpose or from any other context.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")
# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

if [[ "$OS_RELEASE_ID" == "ubuntu" ]]; then
    if [[ -n "$(type -P bats)" ]]; then
        die "Bats _MUST_ not be installed on ubuntu until fixed: https://bugs.launchpad.net/ubuntu/+source/bats/+bug/1882542"
    fi
    bats_version="1.7.0"
    dl_url="https://github.com/bats-core/bats-core/archive/v${bats_version}.tar.gz"
    echo "Installing bats $bats_version"
    curl --fail --location "$dl_url" | tar xz -C /tmp
    pushd /tmp/bats-core-$bats_version
    $SUDO ./install.sh /usr/local  # prints install location
    popd
    rm -rf /tmp/bats-core-$bats_version
fi

echo "Configuring Go environment"
export GOPATH="${GOPATH:-/var/tmp/go}"
mkdir -p "$GOPATH"
export GOSRC=${GOPATH}/src/github.com/containers/podman
export GOCACHE="${GOCACHE:-$GOPATH/cache}"
eval $(go env | tee /dev/stderr)
export PATH="$GOPATH/bin:$PATH"

# shellcheck disable=SC2154
if [[ "$OS_RELEASE_ID" == "fedora" ]]; then
    if [[ $(uname -m) == "x86_64" ]]; then
        msg "Installing swagger binary"
        download_url=$(\
            curl -s https://api.github.com/repos/go-swagger/go-swagger/releases/latest | \
            jq -r '.assets[] | select(.name | contains("linux_amd64")) | .browser_download_url')
        curl --fail -s -o /usr/local/bin/swagger -L'#' "$download_url"
        chmod +x /usr/local/bin/swagger
        /usr/local/bin/swagger version
    fi
fi

# Make pristine for other runtime usage/expectations also save a bit
# of space in the images.
rm -rf "$GOPATH/src" "$GOCACHE"
chown -R root.root "$GOPATH"
