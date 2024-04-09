#!/bin/bash

set -eo pipefail

if [[ -z "$CI" ]] || [[ "$CI" != "true" ]] || [[ -z "$IMG_SFX" ]]; then
    echo "This script is intended to be run by CI and nowhere else."
    exit 1
fi

# This envar is set by the CI system
# shellcheck disable=SC2154
if [[ "$CIRRUS_CHANGE_TITLE" =~ .*CI:DOCS.* ]]; then
    echo "This script must never run after a [CI:DOCS] PR merge"
fi

# Ensure no secrets leak via debugging var expansion
set +x
# This secret envar is set by the CI system
# shellcheck disable=SC2154
echo "$REG_PASSWORD" | \
    skopeo login --password-stdin --username "$REG_USERNAME" "$REGPFX"

declare -a imgnames
imgnames=( imgts imgobsolete imgprune gcsupld get_ci_vm orphanvms ccia )
# A [CI:TOOLING] build doesn't produce CI VM images
if [[ ! "$CIRRUS_CHANGE_TITLE" =~ .*CI:TOOLING.* ]]; then
    imgnames+=( skopeo_cidev fedora_podman prior-fedora_podman )
fi

for imgname in "${imgnames[@]}"; do
    echo "##### Tagging $imgname -> latest"
    # IMG_SFX is defined by CI system
    # shellcheck disable=SC2154
    skopeo copy "docker://$REGPFX/$imgname:c${IMG_SFX}" "docker://$REGPFX/${imgname}:latest"
done
