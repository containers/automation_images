#!/bin/bash

# This script is executed from *_packaging.sh script to install common/shared
# tooling from the containers/podman repository.  It expects
# a go 1.16+ environment has already been set up, and should be called
# as root or through sudo.  The script should not be used for any other
# purpose or from any other context.

set -e

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")
# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

echo "Configuring Go environment"
export GOPATH="${GOPATH:-/var/tmp/go}"
mkdir -p "$GOPATH"
export GOSRC=${GOPATH}/src/github.com/containers/podman
export GOCACHE="${GOCACHE:-$GOPATH/cache}"
eval $(go env | tee /dev/stderr)
export PATH="$GOPATH/bin:$PATH"

echo "Installing runtime tooling"
lilto git clone --quiet https://github.com/containers/podman.git "$GOSRC"

cd "$GOSRC" || die "Podman repo. not cloned to expected directory: '$GOSRC'"
# Calling script already loaded lib.sh
lilto ./hack/install_catatonit.sh
bigto make install.tools

# shellcheck disable=SC2154
if [[ "$OS_RELEASE_ID" == "fedora" ]]; then
    msg "Installing swagger binary"
    download_url=$(\
        curl -s https://api.github.com/repos/go-swagger/go-swagger/releases/latest | \
        jq -r '.assets[] | select(.name | contains("linux_amd64")) | .browser_download_url')
    curl --fail -s -o /usr/local/bin/swagger -L'#' "$download_url"
    chmod +x /usr/local/bin/swagger
    /usr/local/bin/swagger version

    # This is needed for rootless testing
    make install.modules-load
fi

# Make pristine for other runtime usage/expectations also save a bit
# of space in the images.
rm -rf "$GOPATH/src" "$GOCACHE"
chown -R root.root "$GOPATH"
