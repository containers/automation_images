#!/bin/bash

# This script is only intended to be executed by Cirrus-CI, in
# a container, in order to test the functionality of the freshly
# built get_ci_vm container. Any other usage is unlikely to
# function properly.
#
# Example podman command for local testing, using a locally-built
# container image, from top-level repo. directory:
#
# podman run -it --rm -e TESTING_ENTRYPOINT=true -e AI_PATH=$PWD \
#     -e CIRRUS_WORKING_DIR=$PWD -v $PWD:$PWD:O -w $PWD \
#     --entrypoint=get_ci_vm/test.sh get_ci_vm:latest

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "$0")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# Set this non-zero to print test-debug info.
TEST_DEBUG=0
FAILURE_COUNT=0

exit_with_status() {
    if ((FAILURE_COUNT)); then
        echo "Total Failures: $FAILURE_COUNT"
    else
        echo "All tests passed"
    fi
    set -e  # Force exit with exit code
    test "$FAILURE_COUNT" -eq 0
}

# Used internally by test_cmd to assist debugging and output file cleanup
_test_report() {
    local msg="$1"
    local inc_fail="$2"
    local outf="$3"

    if ((inc_fail)); then
        let 'FAILURE_COUNT++'
        echo -n "fail - "
    else
        echo -n "pass - "
    fi

    echo -n "$msg"

    if [[ -r "$outf" ]]; then
        # Ignore output when successful
        if ((inc_fail)) || ((TEST_DEBUG)); then
            echo " (output follows)"
            cat "$outf"
        fi
        rm -f "$outf" "$outf.oneline"
    fi
    echo -e '\n' # Makes output easier to read
}

# Execute an entrypoint.sh function in isolation after calling <harness>
# Capture output and verify exit code and stdout/stderr contents.
# usage: testf <desc.> <harness> <exit code> <output regex> <function> [args...]
# Notes: Exit code not checked if blank.  Expected output will be verified blank
#        if regex is empty.  Otherwise, regex checks whitespace-squashed output.
testf() {
    echo "Testing: ${1:-WARNING: No Test description given}"
    local harness=$2
    local e_exit="$3"
    local e_out_re="$4"
    shift 4

    if ((TEST_DEBUG)); then
        # shellcheck disable=SC2145
        echo "# $@" > /dev/stderr
    fi

    # Using grep -E vs file safer than shell builtin test
    local a_out_f
    local a_exit=0
    a_out_f=$(mktemp -p '' "tmp_${FUNCNAME[0]}_XXXXXXXX")

    # Use a sub-shell to isolate tests from eachother
    set -o pipefail
    # Note: since \$_TMPDIR is defined/set in subshell, this is going to
    # leak them like crazy.  Ignore this since tests should only be running
    # inside a container anyway.
    (
        set -eo pipefail
        # shellcheck source=get_ci_vm/entrypoint.sh disable=SC2154
        source $AI_PATH/get_ci_vm/entrypoint.sh
        status() { /bin/true; }  # not normally useful for testing
        if [[ -n "$harness" ]]; then "$harness"; fi
        "$@" 0<&- |& tee "$a_out_f" | tr -s '[:space:]' ' ' > "${a_out_f}.oneline"
    )
    a_exit="$?"
    if ((TEST_DEBUG)); then
        echo "Command/Function call exited with code: $a_exit"
    fi

    if [[ -n "$e_exit" ]] && [[ $e_exit -ne $a_exit ]]; then
        _test_report "Expected exit-code $e_exit but received $a_exit while executing $1" "1" "$a_out_f"
    elif [[ -z "$e_out_re" ]] && [[ -n "$(<$a_out_f)" ]]; then
        _test_report "Expecting no output from $*" "1" "$a_out_f"
    elif [[ -n "$e_out_re" ]]; then
        if ((TEST_DEBUG)); then
            echo "Received $(wc -l $a_out_f | awk '{print $1}') output lines of $(wc -c $a_out_f | awk '{print $1}') bytes total"
        fi
        if grep -E -q "$e_out_re" "${a_out_f}.oneline"; then
            _test_report "Command $1 exited as expected with expected output" "0" "$a_out_f"
        else
            _test_report "Expecting regex '$e_out_re' match to (whitespace-squashed) output" "1" "$a_out_f"
        fi
    else # Pass
        _test_report "Command $1 exited as expected ($a_exit)" "0" "$a_out_f"
    fi
}


### MAIN

# Check some basic items first and mimic 'testf' output
PASS_MSG=$'pass - Command exited as expected (0)\n'

msg "Testing: Verify \$CIRRUS_WORKING_DIR is non-empty"
req_env_vars CIRRUS_WORKING_DIR
msg "$PASS_MSG"

msg "Testing: Verify \$TESTING_ENTRYPOINT is non-empty"
req_env_vars TESTING_ENTRYPOINT
msg "$PASS_MSG"

msg "Testing: Verify \$AI_PATH is non-empty"
req_env_vars AI_PATH
msg "$PASS_MSG"

set +e

# usage: test_cmd <desc.> <harness> <exit code> <output regex> <function> [args...]
testf "Verify \$AI_PATH/get_ci_vm/entrypoint.sh loads w/o status output" \
    "" 0 "" \
    status

name_root() { NAME="root"; SRCDIR="/tmp"; }
testf "Verify init() fails when \$NAME is root" \
    name_root 1 "Running as root not supported" \
    init

# CIRRUS_WORKING_DIR verified non-empty
# shellcheck disable=SC2154
BAD_TEST_REPO="$CIRRUS_WORKING_DIR/get_ci_vm/bad_repo_test"
bad_repo() { NAME="foobar"; SRCDIR="$BAD_TEST_REPO"; }
testf "Verify init() w/ old/unsupported repo." \
    bad_repo 1 "not compatible" \
    init

GOOD_TEST_REPO="$CIRRUS_WORKING_DIR/get_ci_vm/good_repo_test"
good_repo() { NAME="foobar"; SRCDIR="$GOOD_TEST_REPO"; }
testf "Verify init() w/ apiv1 compatible repo." \
    good_repo 0 "" \
    init

GOOD_TEST_REPO_V2="$CIRRUS_WORKING_DIR/get_ci_vm/good_repo_test_v2"
good_repo_v2() { NAME="snafu"; SRCDIR="$GOOD_TEST_REPO_V2"; }
testf "Verify init() w/ apiv2 compatible repo." \
    good_repo_v2 0 "" \
    init

good_init() {
    NAME="foobar"
    SRCDIR="$GOOD_TEST_REPO"
    CIRRUS_TASK="--list"
    init
}
testf "Verify get_inst_image() returns expected google task name" \
    good_init 0 "google_test" \
    get_inst_image

testf "Verify get_inst_image() returns expected aws task name" \
    good_init 0 "aws_test" \
    get_inst_image

testf "Verify get_inst_image() returns expected container task name" \
    good_init 0 "container_test" \
    get_inst_image

mock_uninit_gcloud() {
    # Don't preserve arguments to make checking easier
    # shellcheck disable=SC2145
    echo "gcloud $@"
    cat $GOOD_TEST_REPO/uninit_gcloud.output
    return 0
}

mock_uninit_gcevm() {
    NAME="foobar"
    SRCDIR="$GOOD_TEST_REPO"
    CIRRUS_TASK="google_test"
    GCLOUD="mock_uninit_gcloud"
    READING_DELAY="0.1s"
    init
    get_inst_image
}

UTC_LOCAL_TEST="-0500"
testf "Verify mock 'gcevm' w/o creds attempts to initialize" \
    mock_uninit_gcevm 1 \
    "WARNING:.+valid GCP credentials.+gcloud.+init.+Mock Google.+ERROR: Unable.+credentials" \
    init_gcevm

mock_gcloud() {
    # Don't preserve arguments to make checking easier
    # shellcheck disable=SC2145
    echo "gcloud $@"
    return 0
}

mock_init_gcevm() {
    NAME="foobar"
    SRCDIR="$GOOD_TEST_REPO"
    CIRRUS_TASK="google_test"
    GCLOUD="mock_gcloud"
    READING_DELAY="0.1s"
    init
    get_inst_image
}


UTC_LOCAL_TEST="-0000"
testf "Verify mock 'gcevm' w/ UTC TZ initializes with delay and warning" \
    mock_init_gcevm 0 'WARNING:.+override \$GCLOUD_ZONE to' \
    init_gcevm

UTC_LOCAL_TEST="-0500"
testf "Verify mock 'gcevm' w/ central TZ initializes as expected" \
    mock_init_gcevm 0 "Winning lottery-number checksum: 0" \
    init_gcevm

mock_gcevm_workflow() {
    init_gcevm
    create_vm
    make_ci_env_script
    make_setup_tarball
    setup_vm
}
# Don't confuse the actual repo. by nesting another repo inside
tar -xzf "$GOOD_TEST_REPO/dot_git.tar.gz" -C "$GOOD_TEST_REPO" .git
# Ignore ownership security checks
git config --system --add safe.directory $GOOD_TEST_REPO
# Setup should tarball new files in the repo.
echo "testing" > "$GOOD_TEST_REPO/uncommited_file"
# Setup should tarball changed files in the repo.
echo -e "\n\ntest file changes\n\n" >> "$GOOD_TEST_REPO/README.md"
# Setup should ignore a removed file
git rm -f "$GOOD_TEST_REPO/uninit_gcloud.output"
# The goal is to match key elements and sequences in the mock output,
# without overly burdening future development.
workflow_regex="\
.*gcloud.+--configuration=automation_images\
.*--image-project=automation_images\
.*--image=test-image-name\
.*foobar-test-image-name\
.*Cloning into\
.*README.md\
.*Ignoring uncommited removed.+uninit_gcloud.output\
.*uncommited_file\
.*Switched to a new branch\
.*gcloud.+compute scp.+root@foobar-test-image-name:/tmp/\
.*gcloud.+compute ssh.+tar.+setup.tar.gz\
.*gcloud.+compute ssh.+chmod.+ci_env.sh\
.*gcloud.+compute ssh.+/root/ci_env.sh.+get_ci_vm.sh --setup"

testf "Verify mock 'gcevm' flavor main() workflow produces expected output" \
    mock_init_gcevm \
    0 "$workflow_regex" \
    mock_gcevm_workflow

# prevent repo. in repo. problems + stray test files
rm -rf "$GOOD_TEST_REPO/.git" "$GOOD_TEST_REPO/uncommited_file"

mock_uninit_aws() {
    # Don't preserve arguments to make checking easier
    # shellcheck disable=SC2145
    echo "aws $@"
    cat $GOOD_TEST_REPO_V2/uninit_aws.output
    return 1
}

mock_uninit_ec2vm() {
    NAME="mctestface"
    SRCDIR="$GOOD_TEST_REPO_V2"
    CIRRUS_TASK="aws_test"
    AWSCLI="mock_uninit_aws"
    init
    get_inst_image
}

testf "Verify mock 'ec2vm' w/o creds attempts to initialize" \
    mock_uninit_ec2vm 1 \
    "WARNING: AWS.+ssh.+initialize" \
    init_ec2vm

mock_init_aws() {
    # Only care if string is present
    # shellcheck disable=SC2199
    if [[ "$@" =~ describe-images ]]; then
        cat $GOOD_TEST_REPO_V2/ami_search.json
    else
        # Don't preserve arguments to make checking easier
        # shellcheck disable=SC2145
        echo "aws $@"
    fi
}

mock_init_ec2vm() {
    NAME="mctestface"
    SRCDIR="$GOOD_TEST_REPO_V2"
    CIRRUS_TASK="aws_test"
    AWSCLI="mock_init_aws"
    EC2_SSH_KEY="$GOOD_TEST_REPO_V2/mock_ec2_key"
    SSH_CMD=true
    init
    get_inst_image
}

testf "Verify mock initialized 'ec2vm' is satisfied with test setup" \
    mock_init_ec2vm 0 "" \
    init_ec2vm

print_select_ec2_inst_image() {
    export A_DEBUG=1
    select_ec2_inst_image
    echo "$INST_IMAGE"
}

testf "Verify AMI selection by name tag with from fake describe-images data" \
    mock_init_ec2vm 0 "ami-newest" \
    print_select_ec2_inst_image

# TODO: Add more EC2 tests

# Must be called last
exit_with_status
