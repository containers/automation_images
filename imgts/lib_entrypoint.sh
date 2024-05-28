#!/usr/bin/env bash

set -e

RED="\e[1;31m"
YEL="\e[1;33m"
NOR="\e[0m"
SENTINEL="__unknown__"  # default set in dockerfile
# Disable all input prompts
# https://cloud.google.com/sdk/docs/scripting-gcloud
GCLOUD="gcloud --quiet"
# https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-options.html#cli-configure-options-list
AWS="aws --cli-connect-timeout 30 --cli-read-timeout 30 --no-paginate"

die() {
    EXIT=$1
    shift
    MSG="$*"
    echo -e "${RED}ERROR: $MSG${NOR}"
    exit "$EXIT"
}

# Similar to die() but it ignores the first parameter (exit code)
# to allow direct use in place of an (otherwise) die() call.
warn() {
    IGNORE=$1
    shift
    MSG="$*"
    echo -e "${RED}WARNING: $MSG${NOR}"
}

# Hilight messages not coming from a shell command
msg() {
    echo -e "${YEL}${1:-NoMessageGiven}${NOR}"
}

# Pass in a list of one or more envariable names; exit non-zero with
# helpful error message if any value is empty
req_env_vars() {
    for i; do
        if [[ -z "${!i}" ]]
        then
            die 1 "entrypoint.sh requires \$$i to be non-empty."
        elif [[ "${!i}" == "$SENTINEL" ]]
        then
            die 2 "entrypoint.sh requires \$$i to be explicitly set."
        fi
    done
}

gcloud_init() {
    req_env_vars GCPJSON GCPPROJECT
    set +xe
    if [[ -n "$1" ]] && [[ -r "$1" ]]
    then
        TMPF="$1"
    else
        TMPF=$(mktemp -p '' .XXXXXXXX)
        trap "rm -f $TMPF &> /dev/null" EXIT
        # Required variable must be set by caller
        # shellcheck disable=SC2154
        echo "$GCPJSON" > $TMPF
    fi
    unset GCPJSON
    # Required variable must be set by caller
    # shellcheck disable=SC2154
    $GCLOUD auth activate-service-account --project="$GCPPROJECT" --key-file="$TMPF" || \
        die 5 "Authentication error, please verify \$GCPJSON contents"
    rm -f $TMPF &> /dev/null || true  # ignore any read-only error
    trap - EXIT
}

aws_init() {
    req_env_vars AWSINI
    set +xe
    if [[ -n "$1" ]] && [[ -r "$1" ]]
    then
        TMPF="$1"
    else
        TMPF=$(mktemp -p '' .$(uuidgen)_XXXX.ini)
    fi
    # shellcheck disable=SC2154
    echo "$AWSINI" > $TMPF
    unset AWSINI
    export AWS_SHARED_CREDENTIALS_FILE=$TMPF
}

# Obsolete and Prune search-loops runs in a sub-process,
# therefor count must be recorded in file.
IMGCOUNT=$(mktemp -p '' imgcount.XXXXXX)
echo "0" > "$IMGCOUNT"
count_image() {
    local count
    count=$(<"$IMGCOUNT")
    let 'count+=1'
    echo "$count" > "$IMGCOUNT"
}

# Cirrus-CI supports multiple methods when specifying an EC2 image
# to use.  This function supports either of them as its only argument:
# Either a literal "ami-*" value, or the value of a "Name" tag to
# search for.  In the former-case, the "ami-*" value will simply
# be printed to stdout.  In the latter case, the newest image
# found by a name-tag search will be printed to stdout.
get_ec2_ami() {
    local image="$1"
    local _awsoutput _name_filter _result_filter
    local -a _awscmd

    _name_filter="Name=name,Values='$image'"
    _result_filter='.Images | map(select(.State == "available")) | sort_by(.CreationDate) | reverse | .[0].ImageId'
    # Word-splitting for $AWS is desired
    # shellcheck disable=SC2206
    _awscmd=(\
        $AWS ec2 describe-images --owners self
        --filters "$_name_filter" --output json
    )

    req_env_vars image AWS

    # Direct image specification, nothing to do.
    if [[ "$image" =~ ^ami-.+ ]]; then printf "$image"; return 0; fi

    # Empty $AWSCLI input to jq will NOT trigger its `-e`, so double-check.
    if  _awsoutput=$("${_awscmd[@]}") && [[ -n "$_awsoutput" ]] && \
        _ami_id=$(jq -r -e "$_result_filter"<<<$_awsoutput) && \
        [[ -n "$_ami_id" ]]
    then
        printf "$_ami_id"
    else
        warn "Could not find an available AMI with name-tag '$image': $_awsoutput"
        return 1
    fi
}

# Takes a tag-name string as the first argument, and a JSON-object (mapping)
# (bash-string) as the second.  If the JSON object contains a "TAGS" key,
# and its value is a list of "Key"/"Value" objects, retrieve and print the
# value associated with a tag-name key, if it exists.  Otherwise print nothing
# and return 1.  Example input JSON:
# {
#   ...ignored stuff...
#   "TAGS": [
#      { "Key: "Foo",
#        "Value": "Bar"
#      }
#   ]
# }
get_tag_value() {
    local tag=$1
    local json=$2
    req_env_vars tag json
    # Careful, there may not be any tag-list at all.
    local tag_filter=".[]? | select(.Key == \"$tag\").Value"
    local tags value

    # There may not be any TAGS key at all.
    if tags=$(jq -e ".TAGS?"<<<"$json"); then
        # All tags are optional, the one we're looking for may not be set
        if value=$(jq -e -r "$tag_filter"<<<"$tags") && [[ -n "$value" ]]; then
            printf "$value"
            return 0
        fi
    fi
    return 1
}
