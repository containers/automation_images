

# This is the entrypoint for the get_ci_vm container image, and
# is only intended to be used inside that context.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
# shellcheck source=./lib.sh
source "$(realpath "$SCRIPT_DIRPATH/../")/lib.sh"

# Don't require users to remember to quote task names
# shellcheck disable=SC2124
CIRRUS_TASK="${CIRRUS_TASK:-$@}"

# These are expected to be passed in to container
SRCDIR="${SRCDIR}"
NAME="${NAME}"

# If defined non-empty, the main() function will not be called
TESTING_ENTRYPOINT="${TESTING_ENTRYPOINT}"

# Assume we're running in a container, so no cleanup is necessary by default
DO_CLEANUP="${DO_CLEANUP:-0}"

# Time to read non-critical but important messages
READING_DELAY="${READING_DELAY:-5s}"

# Set non-zero to enable debugging
A_DEBUG="${A_DEBUG:-0}"

# Required to be non-empty, updated by the supports_apiv*() functions
GET_CI_VM="${GET_CI_VM:-0}"

# Used to cache status of local setup check
CREDENTIALS_ARE_VALID=0

# apiv1 expects to receive the following env. vars. when called with --config
# and $GET_CI_VM is set to 1
#
# Required:
#
# full path where $SRCDIR should be reproduced on the instance
DESTDIR=""
# full URL to project's "upstream" repo.
UPSTREAM_REPO=""
#
# Optional:
#
# path where setup script persists its env. vars
CI_ENVFILE=""
#
# 'gcevm' instances type required:
#
# local gcloud sdk configuration name destinct from other repos.
GCLOUD_CFG=""
# GCE zone to create instances in (may be passed in to container)
GCLOUD_ZONE="${GCLOUD_ZONE}"
# number of CPUs to create instance with
GCLOUD_CPUS=""
# memory quantity to assign to instance (accepts unit suffix)
GCLOUD_MEMORY=""
# size of disk to attach (minimum is 200)
GCLOUD_DISK=""
# GCE Project ID to create instances in
GCLOUD_PROJECT=""
# GCE Project ID where images are stored
GCLOUD_IMGPROJECT=""

# apiv2 expects to receive the following additional env. vars. when
# called with --config and $GET_CI_VM is set to 2
#
# Required:
#
# This holds the name of the AWS config/credentials profile.  This
# is needed because the CLI keeps this data all in a single pair of
# files and the calling user may have AWS already setup for other
# purposes.
AWS_PROFILE=""

status() {
    local message="$1"
    local red="\e[1;31m"
    local yel="\e[1;32m"
    local nor="\e[0m"
    (
        echo ""  # Message should stand out vs any prior output
        echo -e "${red}#${nor} ${yel}${message}${nor}"
    ) > /dev/stderr
}

# Each repository behaves slightly differently, confirm
# compatibility before loading repo-specific settings.
# Specifically, this requires the hack script to define
# a bunch of variables and support specific command-line
# options.  Please see an existing/working example for
# an idea of what the requirements are.
supports_apiv1() {
    req_env_vars REPO_HACK_SCRIPT GET_CI_VM
    dbg "Examining $REPO_HACK_SCRIPT for apiv1 support"
    if [[ ! -r "$REPO_HACK_SCRIPT" ]]; then
        die "Can't find '$REPO_HACK_SCRIPT' in source repository."
    elif ((GET_CI_VM)); then  # Already verified & set
        return 0
    elif grep -Eq '^# get_ci_vm APIv1' "$REPO_HACK_SCRIPT"; then
        dbg "Detected apiv1 support."
        export GET_CI_VM=1  # checked by hack/get_ci_vm.sh
        return 0
    fi
    dbg "Did NOT detect apiv1 support."
    return 1
}

# Requires apiv1 support + specific EC2 support changes
# in the repository.  Specifically, the hack script
# needs to define an AWS_PROFILE and the .cirrus.yml
# EC2 task(s) need to define EC2_INST_TYPE.
supports_apiv2() {
    req_env_vars REPO_HACK_SCRIPT GET_CI_VM
    if ! ((GET_CI_VM)); then
        die "$REPO_HACK_SCRIPT does not support apiv1"
    fi
    dbg "Examining $REPO_HACK_SCRIPT for apiv2 support"
    if grep -Eq '# get_ci_vm APIv2' "$REPO_HACK_SCRIPT"; then
        dbg "Detected apiv2 support."
        export GET_CI_VM=2  # checked by hack/get_ci_vm.sh
        return 0
    fi
    dbg "Did NOT detect apiv2 support."
    return 1
}

init() {
    dbg "Initial env. vars:"
    if ((A_DEBUG)); then show_env_vars; fi
    status "Initializing get_ci_vm"
    # These are passed in by hack/get_ci_vm.sh script
    req_env_vars NAME SRCDIR

    if [[ "$NAME" == "root" ]]; then
        die "Running as root not supported, use your regular user account for identification/auditing purposes"
    fi
    _TMPDIR=$(mktemp -d -p '' get_ci_vm_XXXXXX.tmp)
    dbg "Initializing for \$NAME=$NAME and \$SRCDIR=$SRCDIR and \$_TMPDIR=$_TMPDIR"
    # Several setup functions/commands expect this to be an absolute path
    if [[ "${DESTDIR:0:1}" != "/" ]]; then
        DESTDIR="/$DESTDIR"
    fi

    REPO_HACK_SCRIPT="$SRCDIR/hack/get_ci_vm.sh"
    if supports_apiv1; then  # sets/exports GET_CI_VM=1
        # Dump+Source needed to support in-line comments
        "$REPO_HACK_SCRIPT" --config > $_TMPDIR/apiv1.sh
        dbg "Loading apiv1 vars:
$(cat $_TMPDIR/apiv1.sh)"
        # shellcheck disable=SC1090
        source $_TMPDIR/apiv1.sh
        req_env_vars DESTDIR UPSTREAM_REPO  # CI_ENVFILE is optional.
    else
        die "Repository hack/get_ci_vm.sh not compatible with Api v1"
    fi

    if supports_apiv1 && supports_apiv2; then  # sets/exports GET_CI_VM=2
        "$REPO_HACK_SCRIPT" --config > $_TMPDIR/apiv2.sh
        dbg "Loading apiv2 vars:
$(cat $_TMPDIR/apiv2.sh)"
        # shellcheck disable=SC1090
        source $_TMPDIR/apiv2.sh
        req_env_vars AWS_PROFILE
    fi
}

get_inst_image() {
    local cirrus_tasks
    local _output
    local -a type_image
    status "Obtaining task listing from repository .cirrus.yml"
    req_env_vars SRCDIR
    cirrus_tasks=$(cirrus-ci_env.py --list "$SRCDIR/.cirrus.yml")
    dbg "Successfully loaded .cirrus.yml task listing"
    if [[ -z "$CIRRUS_TASK" ]]; then
        die "Usage: hack/get_ci_vm.sh <task name | --list>
       Note: Quoting the parameter is not required
"
    elif [[ "$CIRRUS_TASK" =~ --list ]]; then
        msg "$cirrus_tasks"
        dbg "Exiting after printing task list"
        exit 0
    elif ! grep -q -- "$CIRRUS_TASK"<<<"$cirrus_tasks"; then
        # The task-list can be long, don't let it swamp the error message"
        dbg "Valid tasks:
$cirrus_tasks"
        die "Unknown .cirrus.yml task name '$CIRRUS_TASK', use '--list' to show valid names."
    fi

    status "Obtaining instance type & image needed by '$CIRRUS_TASK'"
    _output=$(
        cirrus-ci_env.py --inst "$CIRRUS_TASK" "$SRCDIR/.cirrus.yml" | \
        tr '[:space:]' '\n'
    )
    mapfile -t type_image <<<"$_output"
    INST_TYPE="${type_image[0]}"
    INST_IMAGE="${type_image[1]}"
    dbg "Parsed \$type_image=[$_output]"
    if [[ -z "$INST_TYPE" ]] || [[ -z "$INST_IMAGE" ]]; then
        die "Error parsing inst. type and image from output '$_output'"
    fi
}

# Returns true if user has run an 'init' and has a valid token for
# the specific project-id and named-configuration arguments in $PGCLOUD.
has_valid_gcp_credentials() {
    req_env_vars GCLOUD
    dbg "$GCLOUD info output"
    dbg "$($GCLOUD info)"
    if $GCLOUD info |& grep -Eq 'Account:.*None'; then
        return 1
    fi

    # It's possible for 'gcloud info' to list expired credentials,
    # e.g. 'ERROR:  ... invalid grant: Bad Request'
    if $GCLOUD auth print-access-token |& grep -q 'ERROR'; then
        return 1
    fi

    dbg "The user's GCE credentials are valid"
    CREDENTIALS_ARE_VALID=1
    return 0
}

has_valid_aws_credentials() {
    req_env_vars AWSCLI EC2_SSH_KEY
    local _awsoutput _cfgvar
    _awsoutput=$($AWSCLI configure list 2>&1 || true)
    dbg "$AWSCLI configure list"
    dbg "$_awsoutput"
    if egrep -qx 'The config profile.+could not be found'<<<"$_awsoutput"; then
        dbg "AWS config/credentials are missing"
        return 1
    elif [[ ! -r "$EC2_SSH_KEY" ]] || [[ ! -r "${EC2_SSH_KEY}.pub" ]]; then
        dbg "EC2 ssh keys are missing"
        return 1
    else
        # It's possible the config. is incomplete, verify minimums
        for _cfgvar in aws_access_key_id aws_secret_access_key region; do
            # Both unset and empty are the same for our purposes
            if  ! $AWSCLI configure get $_cfgvar &> /dev/null || \
                [[ -z "$($AWSCLI configure get $_cfgvar)" ]]
            then
                dbg "AWS cfg. var. $_cfgvar unset or empty."
                return 1
            fi
            dbg "Found $_cfgvar exists and is set to something."
        done
    fi

    dbg "The user's AWS credentials are valid"
    CREDENTIALS_ARE_VALID=1
    return 0
}

# AWS doesn't have a nice, user-friendly configuration "wizard".
# If an invalid/empty configuration or value is encountered, we
# need a way to invalidate the whole thing so the user can easily
# start over.
invalidate_aws_credentials() {
    req_env_vars AWSCLI EC2_SSH_KEY
    dbg "Wiping out '$AWS_PROFILE' AWS credentials and EC2 get_ci_vm ssh keys"
    local _cfgvar
    rm -f "$EC2_SSH_KEY" "${EC2_SSH_KEY}.pub"
    for _cfgvar in aws_access_key_id aws_secret_access_key region; do
        $AWSCLI configure set $_cfgvar ""
    done
}

setup_aws() {
    local _cfgvar _cfgval _tagspec _keycmd _cmdoutput
    local -a _keycmds
    req_env_vars AWSCLI EC2_SSH_KEY NAME

    warn "\
AWS credentials and/or ssh keys invalid. Attempting to initialize.
Please fill in the following details or ctrl-c to abort.  A
container-runtimes team AWS account login is required, with an
access-key and secret attached.
"
    invalidate_aws_credentials
    # Wipe credentials if setup fails - allow user to attempt again
    # N/B: EXIT trap already in place by main()
    trap invalidate_aws_credentials INT TERM
    for _cfgvar in aws_access_key_id aws_secret_access_key; do
        echo ""
        read -r -s -p "Enter new $_cfgvar value (input hidden): " _cfgval
        echo ""
        # Value will never ever be shorter than about 16 characters
        if [[ "${#_cfgval}" -le 16 ]]; then
            die "Invalid $_cfgvar value (<16 chars)."
        fi
        dbg "Setting $_cfgvar value"
        $AWSCLI configure set $_cfgvar "$_cfgval"
    done
    # EC2 VM images are per-region & our image build workflow only deals
    # with us-east-1 (because anything else would generate multipe AMI IDs).
    # This sucks for basically everyone not network-near this location and
    # there's not a whole damn lot that can be done about it.  There's
    # also no simple way to explain this to users :(
    warn "Forcing interactions to 'us-east-1', because: reasons."
    $AWSCLI configure set region "us-east-1"

    # The GCE CLI (gcloud) conveniently manages ssh keys in a user-friendly,
    # smart and mostly intelligent way.  For AWS, it's all DIY and complex.
    dbg "Generating new ssh keys '$EC2_SSH_KEY' and '${EC2_SSH_KEY}.pub'"
    ssh-keygen -C "$NAME" -f "$EC2_SSH_KEY" -P "" -q -t ed25519

    # Tag required by security-policy. N/B: using the "shorthand" syntax
    # here will cause the command to break if more than one tag is specified.
    _tagspec='ResourceType=key-pair,Tags={Key=automation,Value=false}'
    # I believe 'fileb' is required to do some fancy base64 encoding
    # for some reason.  The --help example says to use it, so we do.
    _keycmds=(\
        "$AWSCLI ec2 delete-key-pair --key-name get_ci_vm-${NAME}"
        "$AWSCLI ec2 import-key-pair --key-name get_ci_vm-${NAME} --public-key-material fileb://${EC2_SSH_KEY}.pub --tag-specifications $_tagspec"
    )
    msg "Attempting to importing EC2 keys"  # Also validate access and permissions
    for _keycmd in "${_keycmds[@]}"; do
        dbg "Executing '$_keycmd'"
        if ! _cmdoutput=$($_keycmd 2>&1); then
            # Make the next-run set everything up again
            invalidate_aws_credentials
            die "Unable to validate AWS access. Are you spelling the key correctly?  Do you have the correct permissions?"
        fi
    done

    # Man page says must clear one sigspec at a time
    trap - INT; trap - TERM
    dbg "New AWS setup complete"
    CREDENTIALS_ARE_VALID=1
}

# We want to efficiently duplicate local repository state on the new
# instance, so we use a shallow clone w/ no extra details. But we
# also need to grab any files not yet committed or tracked.
extra_repo_files() {
    req_env_vars SRCDIR
    cd $SRCDIR &> /dev/null
    git diff --name-only HEAD
    git ls-files . --exclude-standard --others
    cd - &> /dev/null
}

# This script will be transferred to the instance, it defines all necessary
# Cirrus-CI and other env. vars. needed to mimic the automation environment.
make_ci_env_script() {
    status "Preparing the instance's Cirrus-CI environment script"
    req_env_vars _TMPDIR CIRRUS_TASK SRCDIR UPSTREAM_REPO
    mkdir -p "$_TMPDIR/root"
    cd $_TMPDIR/root
    cat <<EOF>ci_env.sh
#!/bin/bash

# Created by get_ci_vm container on $(date --iso-8601=seconds)
# Any manual changes on instance will be preserved, and
# active upon next invocation.

echo "+ Entering Cirrus-CI environment" > /dev/stderr
set -a
$(cirrus-ci_env.py --envs "$CIRRUS_TASK" "$SRCDIR/.cirrus.yml")
CIRRUS_TASK_NAME="$CIRRUS_TASK"
CIRRUS_REPO_CLONE_URL="$UPSTREAM_REPO"
UPSTREAM_REMOTE="upstream"
EOF

if supports_apiv1; then
    cat <<EOF>>ci_env.sh
if [[ -n "$CI_ENVFILE" ]] && [[ -r "$CI_ENVFILE" ]]; then
    echo "+ Loading $CI_ENVFILE"
    source "$CI_ENVFILE";
fi
set +a
echo "+ Changing into $DESTDIR" > /dev/stderr
cd "$DESTDIR"
EOF
    fi

    # Don't resolve env. var. references for this part
    cat <<"EOF">>ci_env.sh
if [[ -n "$@" ]]; then
    # Assume script called by automation, run the command given
    echo "+ Calling $@" > /dev/stderr
    exec "$@"
else
    # Assume script called by human, enter the Cirrus-CI environment
    echo "+ Dropping into a bash login shell inside Cirrus-CI '$CIRRUS_TASK_NAME' task environment"
    exec bash -il
fi
EOF

    # Nothing special needed at the moment for APIv2 setup on the VM.
    # As of this comment, all VMs are setup the same between GCP and AWS

    chmod +x ci_env.sh
    dbg "Produced remote environment script:
$(<ci_env.sh)"
}

# Tarball up current repository state and ci_env.sh script
make_setup_tarball() {
    local extra_file
    local extra_file_path
    local extra_dir_path
    local srcpath
    status "Preparing setup tarball for instance."
    req_env_vars DESTDIR _TMPDIR SRCDIR UPSTREAM_REPO
    mkdir -p "${_TMPDIR}$DESTDIR"
    # We have no way of knowing what state or configuration the user's
    # local repository is in.  Work from a local clone, so we can
    # specify our own setup and prevent unexpected script breakage.
    git clone --no-local --no-hardlinks --depth 1 --single-branch --no-tags "$SRCDIR" "${_TMPDIR}$DESTDIR"
    status "Preparing non-commited repo. files"
    dbg "Handling uncommited files: $(extra_repo_files)"
    extra_repo_files | while read -r extra_file; do
        extra_file_path="$_TMPDIR/$DESTDIR/$extra_file"
        extra_dir_path=$(dirname "$extra_file_path")
        mkdir -p "$extra_dir_path"
        srcpath="${SRCDIR}/$extra_file"
        if [[ -r "$srcpath" ]]; then
            cp -av "$srcpath" "${extra_dir_path}/"
        else
            msg "Ignoring uncommited removed $srcpath"
        fi
    done

    status "Configuring shallow clone of local repository"
    cd "${_TMPDIR}$DESTDIR"
    git config --local alias.st status
    git config --local alias.cm commit
    git config --local alias.co checkout
    git config --local alias.br branch
    git config --local advice.detachedHead false
    git co -b "get_ci_vm"
    git remote add upstream $UPSTREAM_REPO
    git remote remove origin  # Will not exist when tarball extracted
    git config --local --add remote.upstream.fetch \
        "+refs/pull/*/head:refs/remotes/upstream/pr/*"

    # Grab the ci_env script also
    tar -czf "$_TMPDIR/setup.tar.gz" -C "$_TMPDIR" ./root ".$DESTDIR"
}

# APIv1 Supports users overriding $GCLOUD_ZONE to create VMs
# in a non-default zone closer to their location, for faster
# access.  This function handles checking and prompting the user
# when necessary
check_gcevm_tz() {
    req_env_vars GCLOUD_ZONE
    local utc_local
    local utc_base
    local tz_diff
    utc_local="${UTC_LOCAL_TEST:-$(date +%z)}"
    dbg "Timezone check \$utc_local=$utc_local"
    utc_base="-0500" # All Cirrus-CI instances reside in the central zone
    tz_diff=$(python3 -c "print(abs(int('$utc_base', base=10) - int('$utc_local', base=10)))")
    # trigger at 5-zones away from us-central zone (arbitrary guess)
    if grep -q 'central'<<<"$GCLOUD_ZONE" && [[ $tz_diff -ge 500 ]]; then
        warn "
Your local UTC offset ($utc_local) appears distant from the base ($utc_base).

For faster instance access, you should override \$GCLOUD_ZONE to a closer
location.  Valid locations listed at
https://cloud.google.com/compute/docs/regions-zones/#available

e.g. env GCLOUD_ZONE=europe-west3-a hack/get_ci_vm.sh ...
"
        sleep "$READING_DELAY"  # time to read, contimplate, and ctrl-c
    else
        # Goofy easter-egg...utc_base is arbitrary, this helps judge adjustments
        msg "Winning lottery-number checksum: $tz_diff"
    fi
}

_dbg_envars() {
    local env_var_name
    local line
    dbg "debug env. vars.:"
    # Re-splitting elements is intentional
    # shellcheck disable=SC2068
    for env_var_name in $@; do
        line="${env_var_name}=${!env_var_name}"
        dbg "    $line"
    done
}

init_gcevm() {
    local _args
    local _vars
    req_env_vars INST_IMAGE NAME
    if supports_apiv1; then
        _vars="GCLOUD_CFG GCLOUD_ZONE GCLOUD_CPUS GCLOUD_MEMORY"
        _vars="$_vars GCLOUD_DISK GCLOUD_PROJECT GCLOUD_IMGPROJECT"
        _dbg_envars $_vars
        req_env_vars $_vars
    else
        die "Repository hack/get_ci_vm.sh not compatible with 'GCE' instances from this container image."
    fi

    check_gcevm_tz

    # While unlikely, occasionally host/ip and key conflicts occur.
    # These hosts are used for public CI/testing purposes, so we can
    # simply keep this security measure "swept under the rug".
    rm -f "$HOME/.ssh/google_compute_known_hosts"

    INST_NAME="${INST_NAME:-${NAME}-${INST_IMAGE}}"
    DNS_NAME=$INST_NAME  # gcloud compute ssh wrapper will resolve this
    GCLOUD="${GCLOUD:-gcloud} --configuration=$GCLOUD_CFG --project=$GCLOUD_PROJECT"
    _args="--force-key-file-overwrite --strict-host-key-checking=no --zone=$GCLOUD_ZONE"
    SSH_CMD="$GCLOUD compute ssh $_args root@$DNS_NAME --"
    SCP_CMD="$GCLOUD compute scp $_args"
    CREATE_CMD="$GCLOUD compute instances create \
        --zone=$GCLOUD_ZONE --image-project=$GCLOUD_IMGPROJECT \
        --image=$INST_IMAGE --custom-cpu=$GCLOUD_CPUS \
        --custom-memory=$GCLOUD_MEMORY --boot-disk-size=$GCLOUD_DISK \
        --labels=in-use-by=$NAME $INST_NAME"
    CLEANUP_CMD="$GCLOUD compute instances delete --quiet --zone=$GCLOUD_ZONE --delete-disks=all $INST_NAME"

    dbg "Initialized gcevm env. vars:"
    _dbg_envars INST_NAME GCLOUD SSH_CMD SCP_CMD CREATE_CMD CLEANUP_CMD

    status "Confirming and/or configuring GCP access."
    if ! has_valid_gcp_credentials; then
        warn "\
Can't find valid GCP credentials, attempting to (re)initialize.
If asked, please choose '#1: Re-initialize', 'login', and a nearby
GCLOUD_ZONE, otherwise simply follow the prompts.

Note: If asked to set a SSH-key passphrase, DO NOT SET ONE, it
      will make your life miserable! Set an empty password for the key.
"
        $GCLOUD init --project=$GCLOUD_PROJECT --console-only --skip-diagnostics
        if ! has_valid_gcp_credentials; then
            die "Unable to obtain GCP access credentials, please seek assistance."
        fi
    fi
}

get_ec2_inst_type() {
    dbg "Retrieving value for \$EC2_INST_TYPE in .cirrus.yml task '$CIRRUS_TASK'."
    # Don't pollute the script's environment
    (
        eval $(cirrus-ci_env.py --envs "$CIRRUS_TASK" "$SRCDIR/.cirrus.yml")
        echo -n "$EC2_INST_TYPE"
    )
}

init_ec2vm() {
    dbg "Initializing for EC2"
    local _khf _vars _cfgvar _cfgval
    req_env_vars INST_IMAGE NAME
    if supports_apiv1 && supports_apiv2; then
        _dbg_envars AWS_PROFILE
        req_env_vars AWS_PROFILE
        EC2_INST_TYPE=$(get_ec2_inst_type)
        _dbg_envars EC2_INST_TYPE
        # Verify we can obtain the instance type
        [[ -n "$EC2_INST_TYPE" ]] || \
            die "Repository .cirrus.yml env. var. \$EC2_INST_TYPE doesn't exist or is empty for task '$CIRRUS_TASK'."
    else
        die "Repository hack/get_ci_vm.sh not compatible with 'EC2' instances from this container image."
    fi

    # While unlikely, occasionally host/ip and key conflicts occur.
    # These hosts are used for public CI/testing purposes, so we can
    # simply keep this security measure "swept under the rug".
    _khf="$HOME/.ssh/ec2_known_hosts"
    rm -f "$_khf"

    INST_NAME="${INST_NAME:-${NAME}-${INST_IMAGE}}"
    AWSCLI="${AWSCLI:-aws} --profile=$AWS_PROFILE"
    EC2_SSH_KEY="${EC2_SSH_KEY:-$HOME/.ssh/ec2_$AWS_PROFILE}"
    EC2_SSH_ARGS="-i $EC2_SSH_KEY -o StrictHostKeyChecking=no -o CheckHostIP=no -o UserKnownHostsFile=$_khf -o ConnectTimeout=13 -q"
    SSH_CMD="${SSH_CMD:-setup_ec2_ssh_scp}"
    SCP_CMD=""      # defined by setup_ec2_ssh_scp()
    EC2_INST_ID=""  # defined by set_ec2_inst_id()
    DNS_NAME=""     # defined by set_ec2_dns_name()
    # Word-splitting for $AWSCLI is desired
    # shellcheck disable=SC2206
    CREATE_CMD="_ec2_create_vm"
    CLEANUP_CMD="_ec2_cleanup_vm"

    dbg "Initialized ec2vm env. vars:"
    _dbg_envars INST_NAME EC2_INST_TYPE AWSCLI SSH_CMD EC2_SSH_KEY EC2_SSH_ARGS CREATE_CMD CLEANUP_CMD
    status "Confirming and/or configuring AWS access."
    if ! has_valid_aws_credentials; then setup_aws; fi

    select_ec2_inst_image
}

# Updates $EC2_INST_ID on successful lookup of an ec2 instance based on its
# Name tag.  Returns non-zero on lookup failure.
set_ec2_inst_id() {
    local _awsoutput _instfilter _queryfilter _result_filter _state_exclude
    local _ec2_inst_id _ec2_inst_state
    local -a _qcmd
    req_env_vars AWSCLI INST_NAME

    if [[ -n "$EC2_INST_ID" ]]; then
        dbg "Found cached ec2 instance id '$EC2_INST_ID'"
        return 0
    fi

    dbg "Attempting to look up instance ID for '$INST_NAME'"
    # AWS is a horrible mess to use due to insistence on keying
    # every resource by an unreadable, generated IDs, permitting
    # duplicate name-tags, and returning data on meta-states
    # (i.e. "pending", "stopping", and "terminated").  We must use
    # a limited request filter DSL to look up the "Name" tag.
    # Then because the output JSON is a highly-nested blob of
    # cruft we don't care about, we must use a result "query"
    # DSL to help avoid overcomplicating the jq filter any further.
    # https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/describe-instances.html
    _instfilter="Name=tag:Name,Values=$INST_NAME"
    # Valid states are: pending, running, shutting-down, terminated,
    # stopping, and stopped. For the purposes of any caller of this
    # script, we don't care much about pending or terminated.
    _queryfilter="Reservations[*].Instances[*].{ID:InstanceId,ST:State.Name}"
    _state_exclude="[.ST] | inside([\"terminated\",\"pendingr\"]) | not"
    # If there are multiple result matches, and/or some in a transitory
    # state, pick the first one sorted by alphabetical-state, and
    # hope that's good enough.  i.e. prefer "running" over "shutting-down",
    # over "stopping" or "stopped"
    _result_filter="[.[][]] | map(select($_state_exclude)) | sort_by(.ST) | .[0]"
    # Word-splitting for $AWSCLI is desired
    # shellcheck disable=SC2206
    _qcmd=(\
        $AWSCLI ec2 describe-instances
            --filters "$_instfilter"
            --output json
            --no-paginate
            --query "$_queryfilter"
    )

    # Empty $AWSCLI input to jq will NOT trigger its `-e`, so double-check.
    if  _awsoutput=$("${_qcmd[@]}" | jq -e "$_result_filter") && \
        [[ -n "$_awsoutput" ]] && \
        _ec2_inst_id=$(jq -r -e '.ID'<<<$_awsoutput) && \
        _ec2_inst_state=$(jq -r -e '.ST'<<<$_awsoutput) && \
        [[ -n "$_ec2_inst_id" ]]
    then
        EC2_INST_ID="$_ec2_inst_id"
        dbg "Found instance '$INST_NAME' with ID '$EC2_INST_ID' (state: $_ec2_inst_state)"
        return 0
    fi

    dbg "Could not find concrete instance with Name tag '$INST_NAME': '$_awsoutput'"
    EC2_INST_ID=""
    return 1
}

# Updates $DNS_NAME on successful lookup of the public DNS name of a running
# ec2 instance.  Returns non-zero for non-running status or lookup error.
set_ec2_dns_name() {
    local _awsoutput _queryfilter _ec2_dns_name _ec2_inst_state
    local -a _qcmd
    req_env_vars AWSCLI INST_NAME

    if [[ -n "$DNS_NAME" ]]; then
        dbg "Found cached ec2 instance DNS name '$DNS_NAME'"
        return 0
    fi

    dbg "Attempting to look up DNS name for instance '$INST_NAME'"
    # Filter out any instance not in a "running" state since it can't possibly
    # reply to any communication.  Since resources in AWS are keyed
    # by ID, only the first entry (if any) needs to be examined.
    _queryfilter="Reservations[*].Instances[*].{DNS:PublicDnsName,ST:State.Name}"
    if  set_ec2_inst_id &&
        _awsoutput=$($AWSCLI ec2 describe-instances --instance-ids $EC2_INST_ID \
                     --output json --no-paginate --query "$_queryfilter") && \
        [[ -n "$_awsoutput" ]] && \
        _ec2_inst_state=$(jq -r -e '.[0][0].ST'<<<$_awsoutput) && \
        [[ "$_ec2_inst_state" == "running" ]] && \
        _ec2_dns_name=$(jq -r -e '.[0][0].DNS'<<<$_awsoutput) && \
        [[ -n "$_ec2_dns_name" ]]
    then
        DNS_NAME="$_ec2_dns_name"
        dbg "Found DNS name '$DNS_NAME' for instance '$INST_NAME' ID '$EC2_INST_ID'"
        return 0
    fi

    # Failure possible if instance hasn't been fully created or started yet
    dbg "Could not look up instance '$INST_NAME' ID '$EC2_INST_ID' public DNS: '$_awsoutput'"
    DNS_NAME=""
    # It's possible that set_ec2_inst_id() looked up a transitioning or temporarily
    # useless ID.  Force it to do anotherlookup the next time it's called.
    EC2_INST_ID=""
    return 1
}

# Cirrus-CI supports multiple methods when specifying an EC2 image
# to use.  This function supports two of them: Either use the literal
# "ami-*" value, or perform a search against the value as a "Name" tag.
#  In the latter case, the newest image returned will be selected
# and $INST_IMAGE will be updated accordingly.
select_ec2_inst_image() {
    req_env_vars INST_TYPE INST_IMAGE AWSCLI

    # Direct image specification, nothing to do.
    if [[ "$INST_IMAGE" =~ ^ami-.+ ]]; then return 0; fi

    local _awsoutput _name_filter _result_filter
    local -a _qcmd

    dbg "Attempting to look up AMI for image name tag '$INST_IMAGE'"
    _name_filter="Name=name,Values=$INST_IMAGE"
    # Ignore any items not "available", reverse-sort by date, pick 1st item's AMI ID
    _result_filter='.Images | map(select(.State == "available")) | sort_by(.CreationDate) | reverse | .[0].ImageId'
    # Word-splitting for $AWSCLI is desired
    # shellcheck disable=SC2206
    _qcmd=(\
        $AWSCLI ec2 describe-images --owners self
        --filters "$_name_filter" --output json
    )

    # Empty $AWSCLI input to jq will NOT trigger its `-e`, so double-check.
    if  _awsoutput=$("${_qcmd[@]}") && \
        [[ -n "$_awsoutput" ]] && \
        _ami_id=$(jq -r -e "$_result_filter"<<<$_awsoutput) && \
        [[ -n "$_ami_id" ]]
    then
        dbg "Found AMI ID '$_ami_id' with recent name tag '$INST_IMAGE'"
        INST_IMAGE="$_ami_id"
    else
        die "Could not find an available AMI with name tag '$INST_IMAGE': $_awsoutput"
    fi
}

# GCP provides a handy wrapper for ssh and scp, for AWS it's all DIY.
# EC2 instance initial reachability/state of the VM after creation is
# unknown for some time, depending on many factors.  This function
# initializes both $SSH_CMD and $SCP_CMD only when the VM is actually
# reachable.  Accepts zero or more arguments to pass as the remote
# command if instance is reachable.  Returns non-zero on nonexistent
# or unreachable instances.
setup_ec2_ssh_scp() {
    local _args
    _args="$*"  # makes debugging message simpler
    req_env_vars SSH_CMD EC2_SSH_ARGS INST_NAME
    if  [[ -n "$DNS_NAME" ]] || set_ec2_dns_name; then
        # shellcheck disable=SC2145
        SSH_CMD="ssh $EC2_SSH_ARGS -q -t -t root@$DNS_NAME --"
        SCP_CMD="scp $EC2_SSH_ARGS -q"

        dbg "Running '$SSH_CMD $_args'"
        $SSH_CMD "$@"
    else
        # shellcheck disable=SC2145
        dbg "Could not setup \$SSH_CMD or \$SCP_CMD for $INST_NAME.  Will try again."
        SSH_CMD="${FUNCNAME[0]}"
        SCP_CMD=""
        return 1
    fi
}

_ec2_create_vm() {
    req_env_vars AWSCLI EC2_INST_TYPE NAME INST_IMAGE
    # EC2 allows multiple VMs with the same name to exist, get_ci_vm
    # can only work with VMs in the "running" state.  Rely on set_ec2_dns_name()
    # only returning likely network-accessible instances.  Assume a VM in any
    # other state was caused by user-actions, so they're responsible for any
    # odd script behavior (i.e. re-running script "too soon" after rebooting a VM)
    if set_ec2_dns_name; then
        warn "Reusing pre-existing instance '$INST_NAME' with ID '$EC2_INST_ID' at '$DNS_NAME'.  If it's inaccessible, get_ci_vm may behave oddly."
        return 1  # create_vm() expects this behavior
    fi

    # For whatever reason the documented "shorthand" syntax doesn't work
    # reliably with even slightly complex options.  Most of this is basic
    # but must be fully spelled out in all its glorious JSON detail.  If
    # this breaks, maybe the docs will help anybody who has to figure it out:
    # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/block-device-mapping-concepts.html
    cat << EOF > ${_TMPDIR}/mapping.json
[{
  "DeviceName": "/dev/sda1",
  "Ebs": {
    "DeleteOnTermination": true,
    "VolumeSize": 200,
    "VolumeType": "gp2",
    "Encrypted": false
  }
}]
EOF
    # As above, need to spell it all out in detail because >1 tag is required. The
    # tags below are all checked/enforced by custom IAM security policy. Docs:
    # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html#Using_Tags_CLI
    cat << EOF > ${_TMPDIR}/tagspec.json
[{
  "ResourceType": "instance",
  "Tags": [{
      "Key": "Name",
      "Value": "$INST_NAME"
    },{
      "Key": "automation",
      "Value": "false"
    },{
      "Key": "in-use-by",
      "Value": "$NAME"
    }]
}]
EOF

    dbg "Creating a new EC2 VM '$INST_NAME'"
    # This command returns almost immediately, almost always with a
    # zero exit code.  It's left up up to the caller to untangle the
    # output JSON.  Instead, rely on repeated (future) calls to
    # set_ec2_inst_id() and set_ec2_dns_name() to synchronize creation
    # status.
    $AWSCLI ec2 run-instances \
        --block-device-mappings file://${_TMPDIR}/mapping.json \
        --instance-type "$EC2_INST_TYPE" \
        --key-name "get_ci_vm-${NAME}" \
        --image-id "$INST_IMAGE" \
        --associate-public-ip-address \
        --tag-specifications file://${_TMPDIR}/tagspec.json \
        > ${_TMPDIR}/creation.json
}

# Issue the call to create a VM, then sit around and wait a few minutes
# until ssh becomes responsive.  Returns zero if a new VM was created,
# non-zero if a VM already exists, directly-exits on an access timeout.
create_vm() {
    local attempts
    req_env_vars CREATE_CMD SSH_CMD INST_NAME
    # shellcheck disable=SC2145
    dbg "Will execute \$CREATE_CMD=$CREATE_CMD"
    if $CREATE_CMD; then
        attempts=59
        # Allow breaking out of the ssh loop
        trap fini INT
        status "Attempting to access newly created VM, ctrl-c to abort. May take a minute or three."
        dbg "Testing VM accessability with '$SSH_CMD true'"
        while ((attempts)) && ! $SSH_CMD "true"; do
            status "Attempts remaining: $attempts"
            let "attempts--"
            # Some EC2 instances take a long time to become responsive
            if ((attempts)); then sleep 5s; fi
        done
        trap - INT
        if ! ((attempts)); then
            die "Failed to access $INST_NAME with $SSH_CMD true"
        fi
        status "Successfully created new VM '$INST_NAME'."
        return 0
    else
        status "VM already exists or creation failed for '$INST_NAME'."
        return 1
    fi
}

# Upload repository and configure VM environment to mimic CI.
# N/B: This function is ONLY called when VM Creation was successful.
setup_vm() {
    status "Configuring/setting up freshly created $INST_NAME"
    req_env_vars INST_NAME DNS_NAME SCP_CMD _TMPDIR SSH_CMD DESTDIR
    msg "+ Transferring repo. tarball to instance"
    $SCP_CMD "$_TMPDIR/setup.tar.gz" root@${DNS_NAME}:/tmp/
    msg "+ Extracting setup tarball on instance"
    $SSH_CMD tar -xf "/tmp/setup.tar.gz" -C /
    msg "+ Making /root/ci_env.sh script executable"
    $SSH_CMD chmod +x /root/ci_env.sh  # came from tarball
    msg "+ Populating repository remotes"
    $SSH_CMD /root/ci_env.sh git fetch --all --quiet
    msg "+ Executing repo. specific setup instructions."
    if ! $SSH_CMD /root/ci_env.sh env GET_CI_VM=$GET_CI_VM ./hack/get_ci_vm.sh --setup; then
        warn "Instance setup failed or was aborted, proceed with caution!"
    fi
}

_ec2_cleanup_vm() {
    req_env_vars AWSCLI INST_NAME
    if [[ -n "$EC2_INST_ID" ]] || set_ec2_inst_id; then
        $AWSCLI ec2 terminate-instances --instance-ids $EC2_INST_ID > $_TMPDIR/cleanup.json
        return 0
    fi
    dbg "Either no instance named $INST_NAME exists or there was a lookup error."
    # return 0 - VM non-existence is the goal
}

fini_vm() {
    msg "Offering to delete $INST_NAME (might take a minute)
Note: It's perfectly safe to answer 'N'.  Simply re-run script again
with the same task argument, and you can access and/or delete the VM.
"
    read -r -N 1 -p "Are you sure you want to remove $INST_NAME (y/N): " _do_cleanup
    echo ""
    if [[ "$_do_cleanup" != "y" &&  "$_do_cleanup" != "Y" ]]; then
        msg "Keeping VM as-is, please re-run script later to remove it when you're done."
        return 0
    fi
    msg "Deleting $INST_NAME, for GCP this may take a moment or two."
    dbg "Executing \$CLEANUP_CMD=$CLEANUP_CMD"
    if ! $CLEANUP_CMD; then
        warn "Cleanup failed, either $INST_NAME doesn't exist or
you'll need to remove it manually.  Please DO NOT just abandon it:
Ask for help if needed."
    fi
}

fini() {
    local _do_cleanup
    local original_return_value="$?"

    # Finalization errors must be ignored to allow all cleanup operations to occur.
    set +e

    status "Finalizing get_ci_vm"
    if ((CREDENTIALS_ARE_VALID)) && [[ -n "$INST_TYPE" ]] && [[ -n "$INST_IMAGE" ]] \
        && [[ -n "$INST_NAME" ]] && [[ -n "$CLEANUP_CMD" ]]; then
        if [[ "$INST_TYPE" == "gcevm" || "$INST_TYPE" == "ec2vm" ]]; then
            fini_vm
        else
            warn "NOT finalizing unsupported instance type '$INST_TYPE' named '$INST_NAME'"
        fi
    fi

    if [[ -n $A_DEBUG ]] && (($A_DEBUG)) && [[ -d "$_TMPDIR" ]]; then
        status "Not Cleaning up temporary files"
    else
        rm -rf "$_TMPDIR"
    fi

    trap - EXIT
    exit "$original_return_value"
}

main() {
    dbg "Debugging Enabled"
    trap fini EXIT
    init
    get_inst_image
    req_env_vars INST_TYPE
    if [[ "$INST_TYPE" != "gcevm" && "$INST_TYPE" != "ec2vm" ]]; then
        die "Only 'GCE' and 'EC2' instances currently supported, task '$CIRRUS_TASK' uses: '$INST_TYPE'"
    fi

    init_$INST_TYPE
    status "Will attempt to create a '$INST_TYPE' instance named '$INST_NAME'"
    msg "Note: Re-invoking this script will _not_ create additional instances.
Nor will it re-initialize any previously existing.  You will be
given an option to cleanup the instance upon exit.
"

    if create_vm; then
        make_ci_env_script
        make_setup_tarball
        setup_vm
    fi

    status "Accessing instance $INST_NAME: $SSH_CMD"
    req_env_vars SSH_CMD
    # The generated ci_env.sh script simply ensures the important Cirrus-CI
    # env. vars are setup for the user's interactive environment.
    dbg "Using \$SSH_CMD wrapper '$SSH_CMD /root/ci_env.sh'"
    $SSH_CMD /root/ci_env.sh
}

# Allow unit-tests to consume this script like a library.
if [[ -z "$TESTING_ENTRYPOINT" ]]; then
    main
fi
