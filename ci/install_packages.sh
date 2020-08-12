

# This script is intended to be executed as part of the container
# image build process.  Using it under any other context is virtually
# guarantied to cause you much pain and suffering.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
INST_PKGS_FP="$SCRIPT_DIRPATH/install_packages.txt"

die() { echo "ERROR: ${1:-No Error message given}"; exit 1; }

[[ -r "$INST_PKGS_FP" ]] || \
    die "Expecting to find a copy of the file $INST_PKGS_FP"

set -x

dnf update -y
dnf mark remove $(rpm -qa | grep -Ev '(gpg-pubkey)|(dnf)|(sudo)')

# SELinux policy inside container image causes hard to debug packaging problems
dnf install -y --exclude selinux-policy-targeted $(<"$INST_PKGS_FP")
dnf mark install dnf sudo $_

dnf autoremove -y
