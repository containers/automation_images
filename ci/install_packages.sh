

# This script is intended to be executed as part of the container
# image build process.  Using it under any other context is virtually
# guarantied to cause you much pain and suffering.

set -eo pipefail

INST_PKGS_FP=/root/install_packages.txt
INSTED_PKGS_FP=/root/installed_packages.txt

die() { echo "ERROR: ${1:-No Error message given}"; exit 1; }

[[ -r "$INST_PKGS_FP" ]] || \
    die "Expecting to find a copy of the file $INST_PKGS_FP"

set -x

dnf update -y
dnf mark remove $(rpm -qa | grep -Ev '(gpg-pubkey)|(dnf)|(sudo)')

dnf install -y --exclude selinux-policy-targeted $(<"$INST_PKGS_FP")
dnf mark install dnf sudo $_

dnf autoremove -y
dnf clean all
rm -rf /var/cache/dnf
mkdir -p $_

mv "$INST_PKGS_FP" "$INSTED_PKGS_FP"
rm -f "$0"  # Prevent potential accidents
