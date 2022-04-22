#!/bin/bash

# This script is intended to be used by Cirrus-CI, from the VM
# built by the 'image_builder' makefile target in this repo.  Use
# of this script in any other context/environment is unlikely to
# function as intended.

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# shellcheck disable=SC2154
if [[ -z "$CI" ]] || [[ "$CI" != "true" ]] || [[ "$CIRRUS_CI" != "$CI" ]]; then
    die "Unexpected \$CI=$CI and/or \$CIRRUS_CI=$CIRRUS_CI"
elif [[ -z "$IMG_SFX" ]] || [[ -z "$PACKER_BUILDS" ]]; then
    die "Required non-empty values for \$IMG_SFX=$IMG_SFX and \$PACKER_BUILDS=$PACKER_BUILDS"
fi

set_gac_filepath


unset BUILD_PFX
labels=$(get_pr_labels)
# Importing Beta ubuntu or prior-fedora images is not supported.
if [[ "$labels" =~ Beta ]] && [[ "$PACKER_BUILDS" == fedora ]]; then
    echo "Found 'Beta' label on PR, will build Fedora beta VM images."
    BUILD_PFX="beta-"
fi

set -exo pipefail
cd "$REPO_DIRPATH"
export IMG_SFX=$IMG_SFX
export PACKER_BUILDS="${BUILD_PFX}${PACKER_BUILDS}"
make base_images
