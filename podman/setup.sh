

# This script is intended to be executed as part of the container
# image build process.  Using it under any other context is virtually
# guarantied to cause you much pain and suffering.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")
# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

if   [[ "$OS_RELEASE_ID" == "ubuntu" ]]; then
    bash base_images/ubuntu_base-setup.sh
    bash cache_images/ubuntu_setup.sh
elif [[ "$OS_RELEASE_ID" == "fedora" ]]; then
    bash base_images/fedora_base-setup.sh
    bash cache_images/fedora_setup.sh
else
    die "Unknown/unsupported Distro '$OS_RELEASE_ID'"
fi
