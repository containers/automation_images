#!/bin/bash

# This script is intended to be called by the main Makefile
# to wait for and confirm successful import and conversion
# of an uploaded image object from S3 into EC2. It expects
# the path to a file containing the import task ID as the
# first argument.
#
# If the import is successful, the snapshot ID is written
# to stdout. Otherwise, all output goes to stderr, and
# the script exits non-zero on failure or timeout. On
# failure, the file containing the import task ID will
# be removed.

set -eo pipefail

AWS="${AWS:-aws --output json --region us-east-1}"

# The import/conversion process can take a LONG time, have observed
# > 10 minutes on occasion.  Normally, takes 2-5 minutes.
SLEEP_SECONDS=10
TIMEOUT_SECONDS=720

TASK_ID_FILE="$1"

tmpfile=$(mktemp -p '' tmp.$(basename ${BASH_SOURCE[0]}).XXXX)

die() { echo "ERROR: ${1:-No error message provided}" > /dev/stderr; exit 1; }

msg() { echo "${1:-No error message provided}" > /dev/stderr; }

unset snapshot_id
handle_exit() {
    set +e
    rm -f "$tmpfile" &> /dev/null
    if [[ -n "$snapshot_id" ]]; then
        msg "Success ($task_id): $snapshot_id"
        echo -n "$snapshot_id" > /dev/stdout
        return 0
    fi
    rm -f "$TASK_ID_FILE"
    die "Timeout or other error reported while waiting for snapshot import"
}
trap handle_exit EXIT

[[ -n "$AWS_SHARED_CREDENTIALS_FILE" ]] || \
    die "\$AWS_SHARED_CREDENTIALS_FILE must not be unset/empty."

[[ -r "$1" ]] || \
    die "Can't read task id from file '$TASK_ID_FILE'"

task_id=$(<$TASK_ID_FILE)

msg "Waiting up to $TIMEOUT_SECONDS seconds for '$task_id' import.  Checking progress every $SLEEP_SECONDS seconds."
for (( i=$TIMEOUT_SECONDS ; i ; i=i-$SLEEP_SECONDS )); do \

    # Sleep first, to give AWS time to start meaningful work.
    sleep ${SLEEP_SECONDS}s

    $AWS ec2 describe-import-snapshot-tasks \
        --import-task-ids $task_id > $tmpfile

    if  ! st_msg=$(jq -r -e '.ImportSnapshotTasks[0].SnapshotTaskDetail.StatusMessage?' $tmpfile) && \
        [[ -n $st_msg ]] && \
        [[ ! "$st_msg" =~ null ]]
    then
        die "Unexpected result: $st_msg"
    elif egrep -iq '(error)|(fail)' <<<"$st_msg"; then
        die "$task_id: $st_msg"
    fi

    msg "$task_id: $st_msg (${i}s remaining)"

    # Why AWS you use StatusMessage && Status? Bad names! WHY!?!?!?!
    if  status=$(jq -r -e '.ImportSnapshotTasks[0].SnapshotTaskDetail.Status?' $tmpfile) && \
        [[ "$status" == "completed" ]] && \
        snapshot_id=$(jq -r -e '.ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId?' $tmpfile)
    then
        msg "Import complete to: $snapshot_id"
        break
    else
        unset snapshot_id
    fi
done
