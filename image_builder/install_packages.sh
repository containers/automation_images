

# This script is intended to be executed as part of the container
# image build process.  Using it under any other context is virtually
# guarantied to cause you much pain and suffering.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
INST_PKGS_FP="$SCRIPT_DIRPATH/install_packages.txt"
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

[[ -r "$INST_PKGS_FP" ]] || \
    die "Expecting to find a copy of the file $INST_PKGS_FP"

# shellcheck disable=SC2154
[[ -n "$PACKER_VERSION" ]] || \
    die "Expecting a non-empty \$PACKER_VERSION value"

dnf update -y
dnf -y install epel-release
dnf install -y $(<"$INST_PKGS_FP")

install_automation_tooling
