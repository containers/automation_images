#!/bin/bash

# This script is intended to be used by Cirrus-CI, from the container
# built by the ContainerFile in this directory.  Use of this script
# in any other context/environment is unlikely to function as intended.

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# shellcheck disable=SC2154
if [[ -z "$CI" ]] || [[ "$CI" != "true" ]] || [[ "$CIRRUS_CI" != "$CI" ]]; then
    die "Unexpected \$CI=$CI and/or \$CIRRUS_CI=$CIRRUS_CI"
elif [[ -z "$IMG_SFX" ]]; then
    die "Required non-empty values for \$IMG_SFX=$IMG_SFX"
fi

set_gac_filepath

set -exo pipefail
cd "$REPO_DIRPATH"
export IMG_SFX=$IMG_SFX
make image_builder
