#!/bin/bash

# This script is intended to be used by Cirrus-CI, from the VM
# built by the 'image_builder' makefile target in this repo.  Use
# of this script in any other context/environment is unlikely to
# function as intended.

set -e

SCRIPT_FILEPATH=$(realpath "$0")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# When running under Cirrus-CI on a branch, also tag/push "latest" images
PUSH_LATEST=0

# shellcheck disable=SC2154
if [[ -z "$CI" ]] || [[ "$CI" != "true" ]] || [[ "$CIRRUS_CI" != "$CI" ]]; then
    die "Unexpected \$CI='$CI' and/or \$CIRRUS_CI='$CIRRUS_CI'"
elif [[ -z "$IMG_SFX" ]]; then
    die "Script requires non-empty values for \$IMG_SFX='$IMG_SFX'"
elif [[ -z "$TARGET_NAME" ]]; then
    die "Script requiresmakefile target \$TARGET_NAME to be non-empty"
elif [[ -z "$DEST_FQIN" ]]; then
    die "Script requires destination FQIN \$DEST_FQIN to be non-empty"
elif [[ $LOGIN_CMD =~ ENCRYPTED ]]; then
    die "\$LOGIN_CMD did not get decrypted by Cirrus"
elif [[ ${#LOGIN_CMD} -le 5 ]]; then
    die "\$LOGIN_CMD is a ${#LOGIN_CMD}-length string; something almost certainly went wrong with Cirrus decryption"
fi

set -eo pipefail
make "$TARGET_NAME" IMG_SFX=$IMG_SFX

set +x
# Prevent pushing 'latest' images from PRs, only branches and tags
# shellcheck disable=SC2154
if [[ $PUSH_LATEST -eq 1 ]] && [[ -n "$CIRRUS_PR" ]]; then
    echo -e "\nWarning: Refusing to push 'latest' container images from a PR (branches/tags only).\n"
    PUSH_LATEST=0
fi

trap "podman logout --all" EXIT INT CONT
# Out of pure laziness, the entire command is encrypted in Cirrus-CI
${LOGIN_CMD}

set -x
SRC_FQIN="$TARGET_NAME:$IMG_SFX"
podman tag "$SRC_FQIN" "$DEST_FQIN"
podman push "$DEST_FQIN"

if ((PUSH_LATEST)); then
    LATEST_FQIN="${DEST_FQIN%:*}:latest"
    podman tag "$SRC_FQIN" "$LATEST_FQIN"
    podman push "$LATEST_FQIN"
fi
