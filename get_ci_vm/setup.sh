

# This script is intended to be executed as part of the container
# image build process.  Using it under any other context is virtually
# guarantied to cause you much pain and suffering.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")
# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

declare -a PKGS
PKGS=( \
    coreutils
    curl
    gawk
    git
    openssh-client
    py3-yaml
)

apk update
apk upgrade
apk add "${PKGS[@]}"

install_automation_tooling cirrus-ci_env

# For testing updates from a personal branch, use something like this
#TMPDIR=$(mktemp -d)
#git clone -b more_bug_fixes https://github.com/cevich/automation.git "$TMPDIR"
#env INSTALL_PREFIX=/usr/share $TMPDIR/bin/install_automation.sh 0.0.0 cirrus-ci_env
#rm -rf "$TMPDIR"
