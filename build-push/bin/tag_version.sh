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
req_env_vars SCRIPT_FILEPATH RUNTIME PLATFORMOS FQIN CONTEXT \
             PUSH ARCHES REGSERVER NAMESPACE IMGNAME MODCMD

# As in main.sh, the context name comes from subdir basename
# shellcheck disable=SC2154
CTX_NAME=$(basename "$CONTEXT")  # upstream, testing, or stable

# shellcheck disable=SC2154
dbg "Mod-command operating on $FQIN in $CTX_NAME context"

if [[ "$CTX_NAME" == "stable" ]]; then
    # Stable images must all be tagged with a version number.
    # Confirm this value is passed in by shell env. var. since
    # retrieving it from the image content is beyond the scope
    # of this script.
    req_env_vars img_cmd_version
    img_cmd_version=v${img_cmd_version#v}
    if egrep -q '^v[0-9]+\.[0-9]+\.[0-9]+'<<<"$img_cmd_version"; then
        msg "Found image command version '$img_cmd_version'"
    else
        die "Encountered unexpected/non-conforming version '$img_cmd_version'"
    fi

    # shellcheck disable=SC2154
    $RUNTIME tag $FQIN:latest $FQIN:$img_cmd_version
    msg "Successfully tagged $FQIN:$img_cmd_version"

    # Tag as x.y to provide a consistent tag even for a future z+1
    xy_ver=$(awk -F '.' '{print $1"."$2}'<<<"$img_cmd_version")
    $RUNTIME tag $FQIN:latest $FQIN:$xy_ver
    msg "Successfully tagged $FQIN:$xy_ver"

    # Tag as x to provide consistent tag even for a future y+1
    x_ver=$(awk -F '.' '{print $1}'<<<"$xy_ver")
    $RUNTIME tag $FQIN:latest $FQIN:$x_ver
    msg "Successfully tagged $FQIN:$x_ver"
else
    warn "Not tagging '$CTX_NAME' context of '$FQIN'"
fi
