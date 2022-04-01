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
    # shellcheck disable=SC2154
    msg "Found image command version '$img_cmd_version'"
    # shellcheck disable=SC2154
    $RUNTIME tag $FQIN:latest $FQIN:v${img_cmd_version#v}
    msg "Successfully tagged $FQIN:v${img_cmd_version#v}"
else
    warn "Not tagging '$CTX_NAME' context of '$FQIN'"
fi
