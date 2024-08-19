

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
# Allow erasing pre-installed curl-minimal package
dnf install -y --allowerasing $(<"$INST_PKGS_FP")

# As of 2024-04-24 installing the EPEL `awscli` package results in error:
# nothing provides python3.9dist(docutils) >= 0.10
# Grab the binary directly from amazon instead
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
AWSURL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
cd /tmp
curl --fail --location -O "${AWSURL}"
# There's little reason to see every single file extracted
unzip -q awscli*.zip
./aws/install -i /usr/local/share/aws-cli -b /usr/local/bin
rm -rf awscli*.zip ./aws

install_automation_tooling
