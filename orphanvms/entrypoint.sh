#!/usr/bin/env bash

# This script is set as, and intended to run as the `orphanvms` container's
# entrypoint.  It searches for active VM instances with an "old" `creation`
# timestamp - where "old" is a completely arbitrary several days :)

set -eo pipefail

# shellcheck source=imgts/lib_entrypoint.sh
source /usr/local/bin/lib_entrypoint.sh

# set this to 1 to enable
A_DEBUG="${A_DEBUG:-0}"
if ((A_DEBUG)); then msg "Warning: Debugging is enabled"; fi

req_env_var GCPJSON GCPNAME GCPPROJECT GCPPROJECTS AWSINI

NOW=$(date +%s)
TOO_OLD='3 days ago'  # Detect Friday Orphans on Monday
EVERYTHING=${EVERYTHING:-0}  # set to '1' for testing
if ((EVERYTHING)); then
    TOO_OLD="3 seconds ago"
fi
# Anything older than this is "too old"
THRESHOLD=$(date --date="$TOO_OLD" --iso-8601=minute)

dbg() {
    if ((A_DEBUG)); then
        (
        echo
        # There's lots of looping going on in this script with left-justified output.
        # Offset debugging messages so they have more context.
        echo "    ${1:-No debugging message given}"
        ) > /dev/stderr
    fi
}

# shellcheck source=orphanvms/gce
. /usr/local/bin/_gce
# shellcheck source=orphanvms/ec2
. /usr/local/bin/_ec2
