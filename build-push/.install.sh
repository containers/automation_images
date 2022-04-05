#!/bin/bash

# This script is intended to be used from two places only:
# 1) When building the build-push VM image, to install the scripts as-is
#    in a PR in order for CI testing to operate on them.
# 2) From the autoupdate.sh script, when $BUILDPUSHAUTOUPDATED is unset
#    or '0'.  This clones the latest repository to install (possibly)
#    updated scripts.
#
# WARNING: Use under any other circumstances will probably screw things up.

if [[ -z "$BUILDPUSHAUTOUPDATED" ]];
then
    echo "This script must only be run under Packer or autoupdate.sh"
    exit 1
fi

source /etc/automation_environment

#shellcheck disable=SC2154
cd $(dirname "$SCRIPT_FILEPATH") || exit 1
# Must be installed into $AUTOMATION_LIB_PATH/../bin which is on $PATH
cp ./bin/* $AUTOMATION_LIB_PATH/../bin/
cp ./lib/* $AUTOMATION_LIB_PATH/
chmod +x $AUTOMATION_LIB_PATH/../bin/*
