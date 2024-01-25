

# This script is intended to be executed as part of the container
# image build process.  Using it under any other context is virtually
# guaranteed to cause you much pain and suffering.

set -xeo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")
# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

declare -a PKGS
PKGS=( \
    aws-cli
    coreutils
    curl
    gawk
    git
    jq
    openssh-client
    python3
    py3-yaml
    py3-pip
)

apk update
apk upgrade
apk add --no-cache "${PKGS[@]}"
rm -rf /var/cache/apk/*

aws --version  # Confirm that aws actually runs

install_automation_tooling cirrus-ci_env

# For testing updates from a personal branch, use something like this
#TMPDIR=$(mktemp -d)
#BRANCH=fix_osx_again
#git clone -b $BRANCH https://github.com/cevich/automation.git "$TMPDIR"
#env INSTALL_PREFIX=/usr/share $TMPDIR/bin/install_automation.sh 0.0.0 cirrus-ci_env
#rm -rf "$TMPDIR"
