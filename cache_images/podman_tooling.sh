
# This script is sourced from *_packaging.sh script to install common/shared
# tooling from the containers/podman repository.  It expects
# a go 1.13+ environment has already been setup.  The script should
# not be used for any other purpose or from any other context.

echo "Installing runtime tooling"
export GOPATH="${GOPATH:/var/tmp/go}"
export GOSRC=/var/tmp/go/src/github.com/containers/podman
export GOCACHE="${GOCACHE:-/root/.cache/go-build}"
lilto git clone --quiet https://github.com/containers/podman.git "$GOSRC"

cd "$GOSRC" || die "Podman repo. not cloned to expected directory: '$GOSRC'"
# Calling script already loaded lib.sh
# shellcheck disable=SC2154
lilto $SUDO ./hack/install_catatonit.sh
bigto $SUDO make install.tools

# shellcheck disable=SC2154
if [[ "$OS_RELEASE_ID" == "ubuntu" ]]; then
    lilto $SUDO make install.libseccomp.sudo
else  # Fedora
    msg "Installing swagger binary"
    download_url=$(\
        curl -s https://api.github.com/repos/go-swagger/go-swagger/releases/latest | \
        jq -r '.assets[] | select(.name | contains("linux_amd64")) | .browser_download_url')
    $SUDO curl --fail -s -o /usr/local/bin/swagger -L'#' "$download_url"
    $SUDO chmod +x /usr/local/bin/swagger
    /usr/local/bin/swagger version
fi

# Make pristine for other runtime usage/expectations also save a bit
# of space in the images.
$SUDO rm -rf "$GOPATH/src" "$GOCACHE"
$SUDO chown -R root.root /var/tmp/go
