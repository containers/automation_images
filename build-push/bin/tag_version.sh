#!/bin/bash

# This script is not intended for humans.  It should only be referenced
# as an argument to the build-push.sh `--modcmd` option.  It's purpose
# is to ensure stable images are re-tagged with a verison-number
# cooresponding to the included tool's version.

set -eo pipefail

if [[ -r "/etc/automation_environment" ]]; then
    source /etc/automation_environment  # defines AUTOMATION_LIB_PATH
    #shellcheck disable=SC1090,SC2154
    source "$AUTOMATION_LIB_PATH/common_lib.sh"
else
    echo "Unexpected operating environment"
    exit 1
fi

# Vars defined by build-push.sh spec. for mod scripts
req_env_vars SCRIPT_FILENAME SCRIPT_FILEPATH RUNTIME PLATFORMOS FQIN CONTEXT \
             PUSH ARCHES REGSERVER NAMESPACE IMGNAME MODCMD

if [[ "$#" -ge 1 ]]; then
    FLAVOR_NAME="$1"  # upstream, testing, or stable
fi

if [[ "$#" -ge 2 ]]; then
    # Enforce all version-tags start with a 'v'
    VERSION="v${2#v}"  # output of $version_cmd
fi

if [[ -z "$FLAVOR_NAME" ]]; then
    # Defined by common_lib.sh
    # shellcheck disable=SC2154
    warn "$SCRIPT_FILENAME passed empty flavor-name argument (optional)."
elif [[ -z "$VERSION" ]]; then
    warn "$SCRIPT_FILENAME received empty version argument (req. for FLAVOR_NAME=stable)."
fi

# shellcheck disable=SC2154
dbg "Mod-command operating on $FQIN in '$FLAVOR_NAME' flavor"

if [[ "$FLAVOR_NAME" == "stable" ]]; then
    # Stable images must all be tagged with a version number.
    # Confirm this value is passed in by caller.
    req_env_vars VERSION
    VERSION=v${VERSION#v}
    if egrep -q '^v[0-9]+\.[0-9]+\.[0-9]+'<<<"$VERSION"; then
        msg "Found image command version '$VERSION'"
    else
        die "Encountered unexpected/non-conforming version '$VERSION'"
    fi

    # shellcheck disable=SC2154
    $RUNTIME tag $FQIN:latest $FQIN:$VERSION
    msg "Successfully tagged $FQIN:$VERSION"

    # Tag as x.y to provide a consistent tag even for a future z+1
    xy_ver=$(awk -F '.' '{print $1"."$2}'<<<"$VERSION")
    $RUNTIME tag $FQIN:latest $FQIN:$xy_ver
    msg "Successfully tagged $FQIN:$xy_ver"

    # Tag as x to provide consistent tag even for a future y+1
    x_ver=$(awk -F '.' '{print $1}'<<<"$xy_ver")
    $RUNTIME tag $FQIN:latest $FQIN:$x_ver
    msg "Successfully tagged $FQIN:$x_ver"
else
    warn "$SCRIPT_FILENAME not version-tagging for '$FLAVOR_NAME' stage of '$FQIN'"
fi
