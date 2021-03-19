

# This is the entrypoint for the get_ci_vm container image, and
# is only intended to be used inside that context.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
# shellcheck source=./lib.sh
source "$(realpath "$SCRIPT_DIRPATH/../")/lib.sh"

# Don't require users to remember to quote task names
# shellcheck disable=SC2124
CIRRUS_TASK="$@"

# These are expected to be passed in to container
SRCDIR="${SRCDIR}"
NAME="${NAME}"

# If defined non-empty, the main() function will not be called
TESTING_ENTRYPOINT="${TESTING_ENTRYPOINT}"

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
# path where setup script persists it's env. vars
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
# compatibility before loading repo-specific settings
supports_apiv1() {
    req_env_vars REPO_HACK_SCRIPT
    if [[ ! -r "$REPO_HACK_SCRIPT" ]]; then
        die "Can't find '$REPO_HACK_SCRIPT' in source repository."
    elif grep -Eq '^# get_ci_vm APIv1' "$REPO_HACK_SCRIPT"; then
        return 0
    fi
    return 1
}

init() {
    status "Initializing get_ci_vm"
    # These are passed in by hack/get_ci_vm.sh script
    req_env_vars NAME SRCDIR

    if [[ "$NAME" == "root" ]]; then
        die "Running as root not supported, use your regular user account for identification/auditing purposes"
    fi

    # Assume we're running in a container, so no cleanup is necessary by default
    DO_CLEANUP="${DO_CLEANUP:-0}"
    _TMPDIR=$(mktemp -d -p '' get_ci_vm_XXXXXX.tmp)
    # Several setup functions/commands expect this to be an absolute path
    if [[ "${DESTDIR:0:1}" != "/" ]]; then
        DESTDIR="/$DESTDIR"
    fi

    REPO_HACK_SCRIPT="$SRCDIR/hack/get_ci_vm.sh"
    if supports_apiv1; then
        # Dump+Source needed to support in-line comments
        env GET_CI_VM=1 "$REPO_HACK_SCRIPT" --config > $_TMPDIR/apiv1.sh
        # shellcheck disable=SC1090
        source $_TMPDIR/apiv1.sh
        req_env_vars DESTDIR UPSTREAM_REPO
        # CI_ENVFILE is optional.
    else
        die "Repository hack/get_ci_vm.sh not compatible with this container image."
    fi
}

get_inst_image() {
    local cirrus_tasks
    local _output
    local -a type_image
    status "Obtaining task listing from repository .cirrus.yml"
    req_env_vars SRCDIR
    cirrus_tasks=$(cirrus-ci_env.py --list "$SRCDIR/.cirrus.yml")

    if [[ -z "$CIRRUS_TASK" ]]; then
        die "Usage: hack/get_ci_vm.sh <task name | --list>
       Note: Quoting the parameter is not required
"
    elif [[ "$CIRRUS_TASK" =~ "--list" ]]; then
        msg "$cirrus_tasks"
        exit 0
    elif ! grep -q "$CIRRUS_TASK"<<<"$cirrus_tasks"; then
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
    if [[ -z "$INST_TYPE" ]] || [[ -z "$INST_IMAGE" ]]; then
        die "Error parsing inst. type and image from output '$_output'"
    fi
}

# Returns true if user has run an 'init' and has a valid token for
# the specific project-id and named-configuration arguments in $PGCLOUD.
has_valid_credentials() {
    req_env_vars GCLOUD
    if $GCLOUD info |& grep -Eq 'Account:.*None'; then
        return 1
    fi

    # It's possible for 'gcloud info' to list expired credentials,
    # e.g. 'ERROR:  ... invalid grant: Bad Request'
    if $GCLOUD auth print-access-token |& grep -q 'ERROR'; then
        return 1
    fi

    return 0
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
    chmod +x ci_env.sh
}

# Tarball up current repository state and ci_env.sh script
make_setup_tarball() {
    status "Preparing setup tarball for instance."
    req_env_vars DESTDIR _TMPDIR SRCDIR UPSTREAM_REPO
    mkdir -p "${_TMPDIR}$DESTDIR"
    git clone --no-local --no-hardlinks --depth 1 --single-branch --no-tags "$SRCDIR" "${_TMPDIR}$DESTDIR"
    extra_repo_files | while read -r extra_file; do
        extra_file_path="$_TMPDIR/$DESTDIR/$extra_file"
        extra_dir_path=$(dirname "$extra_file_path")
        mkdir -p "$extra_dir_path"
        cp -av "${SRCDIR}/$extra_file" "${extra_dir_path}/"
    done

    status "Configuring shallow clone of local repository"
    cd "${_TMPDIR}$DESTDIR"
    git config --local alias.st status
    git config --local alias.cm commit
    git config --local alias.co checkout
    git config --local alias.br branch
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
        sleep 5s  # time to read, contimplate, and ctrl-c
    else
        # Goofy easter-egg...utc_base is arbitrary, this helps judge adjustments
        msg "Winning lottery-number checksum: $tz_diff"
    fi
}

init_gcevm() {
    local _args
    if supports_apiv1; then
        req_env_vars GCLOUD_CFG GCLOUD_ZONE GCLOUD_CPUS GCLOUD_MEMORY
        req_env_vars GCLOUD_DISK GCLOUD_PROJECT GCLOUD_IMGPROJECT
    else
        die "Repository hack/get_ci_vm.sh not compatible 'gcevm' instances from this container image."
    fi
    req_env_vars INST_IMAGE NAME GCLOUD_CFG GCLOUD_PROJECT GCLOUD_ZONE GCLOUD_CPUS GCLOUD_MEMORY GCLOUD_DISK

    check_gcevm_tz

    # While unlikely, occasionally host/ip and key conflicts occur.
    # These hosts are used for public CI/testing purposes, so we can
    # simply keep this security measure "swept under the rug".
    rm -f "$HOME/.config/gcloud/ssh/google_compute_known_hosts"

    INST_NAME="${INST_NAME:-${NAME}-${INST_IMAGE}}"
    GCLOUD="gcloud --configuration=$GCLOUD_CFG --project=$GCLOUD_PROJECT"
    _args="--force-key-file-overwrite --strict-host-key-checking=no --zone=$GCLOUD_ZONE"
    SSH_CMD="$GCLOUD compute ssh $_args root@$INST_NAME"
    SCP_CMD="$GCLOUD compute scp $_args"
    CREATE_CMD="$GCLOUD compute instances create \
--zone=$GCLOUD_ZONE --image-project=$GCLOUD_IMGPROJECT \
--image=$INST_IMAGE --custom-cpu=$GCLOUD_CPUS --custom-memory=$GCLOUD_MEMORY \
--boot-disk-size=$GCLOUD_DISK --labels=in-use-by=$NAME $INST_NAME"
    CLEANUP_CMD="$GCLOUD compute instances delete --zone=$GCLOUD_ZONE --delete-disks=all $INST_NAME"
    if ! has_valid_credentials; then
        warn "Can't find valid GCP credentials, attempting to (re)initialize.
If asked, please choose \"#1: Re-initialize\", \"login\", and \"$GCLOUD_ZONE\" GCLOUD_ZONE,
otherwise simply follow the prompts"
        $GCLOUD init --project=$GCLOUD_PROJECT --console-only --skip-diagnostics
        if ! has_valid_credentials; then
            die "Unable to obtain GCP access credentials, please seek assistance."
        fi
    fi
}

# Returns 0 if a VM was created, non-0 if not, directly-exits on error.
create_gcevm() {
    local attempts
    req_env_vars CREATE_CMD SSH_CMD INST_NAME
    if $CREATE_CMD; then
        attempts=10
        # Allow breaking out of the ssh loop
        trap "die 'Exiting due to ctrl-c being pressed, WARNING: VM not removed!'" INT
        status "Attempting to access newly created VM, ctrl-c to abort. May take a minute or two."
        while ((attempts)) && ! $SSH_CMD --command "true"; do
            status "Attempts remaining: $attempts"
            let "attempts--"
            if ((attempts)); then sleep 3s; fi
        done
        trap - INT
        if ! ((attempts)); then
            die "Failed to access $INST_NAME with $SSH_CMD"
        fi
        return 0
    else
        return 1
    fi
}

setup_gcevm() {
    status "Configuring/setting up freshly create $INST_NAME"
    req_env_vars INST_NAME SCP_CMD _TMPDIR SSH_CMD DESTDIR
    msg "+ Transferring repo. tarball to instance"
    $SCP_CMD "$_TMPDIR/setup.tar.gz" root@${INST_NAME}:/tmp/
    msg "+ Extracting setup tarball on instance"
    $SSH_CMD -- tar -xf "/tmp/setup.tar.gz" -C /
    msg "+ Making /root/ci_env.sh script executable"
    $SSH_CMD -- chmod +x /root/ci_env.sh  # came from tarball
    msg "+ Populating repository remotes"
    $SSH_CMD -- /root/ci_env.sh git fetch --all --quiet
    msg "+ Executing repo. specific setup instructions."
    if ! $SSH_CMD -- /root/ci_env.sh env GET_CI_VM=1 ./hack/get_ci_vm.sh --setup; then
        warn "Instance setup failed for some reason, proceed with caution."
    fi
}

fini_gcevm() {
    req_env_vars INST_NAME CLEANUP_CMD
    msg "
Offering to delete $INST_NAME (might take a minute)
Note: It's perfectly safe to answer 'N'.  Simply re-run script again
later with the same arguments, to access and/or delete the VM.
"
    $CLEANUP_CMD || true # prompts for Yes/No; ignore errors
}

fini() {
    local original_return_value="$?"
    set +e  # Finalization errors are all non-fatal
    status "Finalizing get_ci_vm"
    if [[ -n "$INST_TYPE" ]] && [[ -n "$INST_IMAGE" ]] \
        && [[ -n "$INST_NAME" ]] && [[ -n "$CLEANUP_CMD" ]]; then
        if [[ "$INST_TYPE" == "gcevm" ]]; then
            fini_$INST_TYPE
        else
            warn "NOT finalizing unsupported instance type '$INST_TYPE' named '$INST_NAME'"
        fi
    fi
    if [[ -n $DO_CLEANUP ]] && (($DO_CLEANUP)) && [[ -d "$_TMPDIR" ]]; then
        status "Cleaning up temporary files"
        rm -rf "$_TMPDIR"
    fi
    exit "$original_return_value"
}
trap fini EXIT


main() {
    init
    get_inst_image
    req_env_vars INST_TYPE
    if [[ "$INST_TYPE" != "gcevm" ]]; then
        die "Only 'gcevm' instances currently supported, task '$CIRRUS_TASK' uses: '$INST_TYPE'"
    fi

    init_$INST_TYPE
    status "Will attempt to create a '$INST_TYPE' instance named '$INST_NAME'"
    msg "Note: Re-invoking this script will _not_ create additional instances.
Nor will it re-initialize any previously existing.  You will be
given an option to cleanup the instance upon exit.
"

    if create_$INST_TYPE; then
        make_ci_env_script
        make_setup_tarball
        setup_$INST_TYPE
    fi

    status "Accessing instance $INST_NAME"
    req_env_vars SSH_CMD
    $SSH_CMD -- /root/ci_env.sh
}

if [[ -z "$TESTING_ENTRYPOINT" ]]; then
    main
fi
