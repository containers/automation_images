

# DO NOT USE - This script is intended to be called by the Cirrus-CI
# `test_build-push` task.  It is not intended to be used otherwise
# and may cause harm.  It's purpose is to confirm the 'main.sh' script
# behaves in an expected way, given a local test repository as input.

set -e
SCRIPT_DIRPATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
source $SCRIPT_DIRPATH/../lib.sh

req_env_vars CIRRUS_CI

# No need to test if image wasn't built
if TARGET_NAME=build-push skip_on_pr_label; then exit 0; fi

# Architectures to test with (golang standard names)
TESTARCHES="amd64 arm64"
# main.sh is sensitive to this value
ARCHES=$(tr " " ","<<<"$TESTARCHES")
export ARCHES
# Contrived "version" for testing purposes
FAKE_VER_X=$RANDOM
FAKE_VER_Y=$RANDOM
FAKE_VER_Z=$RANDOM
FAKE_VERSION="$FAKE_VER_X.$FAKE_VER_Y.$FAKE_VER_Z"
# Contrived source repository for testing
SRC_TMP=$(mktemp -p '' -d tmp-build-push-test-XXXX)
# Do not change, main.sh is sensitive to the 'testing' name
TEST_FQIN=example.com/testing/stable
# Stable build should result in manifest list tagged this
TEST_FQIN2=example.com/containers/testing
# Don't allow main.sh or tag_version.sh to auto-update at runtime
export BUILDPUSHAUTOUPDATED=1

trap "rm -rf $SRC_TMP" EXIT

# main.sh expects $PWD to be a git repository.
msg "
##### Constructing local test repository #####"
cd $SRC_TMP
showrun git init -b main testing
cd testing
git config --local user.name "Testy McTestface"
git config --local user.email "test@example.com"
git config --local advice.detachedHead "false"
git config --local commit.gpgsign "false"
# The following paths match the style of sub-dir in the actual
# skopeo/buildah/podman repositories.  Only the 'stable' flavor
# is tested here, since it involves the most complex workflow.
mkdir -vp "contrib/testimage/stable"
cd "contrib/testimage/stable"
echo "build-push-test version v$FAKE_VERSION" | tee "FAKE_VERSION"
cat <<EOF | tee "Containerfile"
FROM registry.fedoraproject.org/fedora:latest
ADD /FAKE_VERSION /
RUN dnf install -y iputils
EOF
cd $SRC_TMP/testing
git add --all
git commit -m 'test repo initial commit'

msg "
##### Testing build-push multi-arch build of '$TEST_FQIN'/'$TEST_FQIN2' #####"
buildah --version
export DRYRUN=1  # Force main.sh not to push anything
req_env_vars ARCHES DRYRUN
# main.sh is sensitive to 'testing' value.
# also confirms main.sh is on $PATH
env A_DEBUG=1 main.sh git://testing contrib/testimage/stable

# Because this is a 'stable' image, verify that main.sh will properly
# version-tagged both FQINs.  No need to check 'latest'.
msg "
##### Testing execution of images arches $TESTARCHES #####"
podman --version
req_env_vars TESTARCHES FAKE_VERSION TEST_FQIN TEST_FQIN2
for _fqin in $TEST_FQIN $TEST_FQIN2; do
    for _arch in $TESTARCHES; do
        # As of podman 3.4.4, the --arch=$arch argument will cause failures
        # looking up the image in local storage.  This bug is fixed in later
        # versions.  For now, query the manifest directly for the image sha256.
        _q='.manifests[] | select(.platform.architecture == "'"$_arch"'") | .digest'
        _s=$(podman manifest inspect $_fqin:v$FAKE_VERSION | jq -r "$_q")
        msg "Found '$_arch' in manifest-list $_fqin:v$FAKE_VERSION as digest $_s"
        if [[ -z "$_s" ]]; then
            die "Failed to get sha256 for FQIN '$_fqin:v$FAKE_VERSION' ($_arch)"
        fi
        msg "Testing container can ping localhost"
        showrun podman run -i --rm "$_fqin@$_s" ping -q -c 1 127.0.0.1

        xy_ver="v$FAKE_VER_X.$FAKE_VER_Y"
        msg "Testing tag '$xy_ver'"
        if ! podman manifest inspect $_fqin:$xy_ver &> /dev/null; then
            die "Failed to find manifest-list tagged '$xy_ver'"
        fi

        x_ver="v$FAKE_VER_X"
        msg "Testing tag '$x_ver'"
        if ! podman manifest inspect $_fqin:$x_ver &> /dev/null; then
            die "Failed to find manifest-list tagged '$x_ver'"
        fi

        #TODO: Test org.opencontainers.image.source value
        #TODO: fails, returns null for some reason
        #msg "Confirming version-label matches tag"
        #_q='.[0].Labels."org.opencontainers.image.version"'
        #_v=$(podman image inspect "$_fqin@$_s" | jq -r "$_q")
        #showrun test $_v -eq $FAKE_VERSION
    done
done

# This script verifies it's only/ever running inside CI.  Use a fake
# main.sh to verify it auto-updates itself w/o actually performing
# a build.  N/B: This test must be run last, in a throw-away environment,
# it _WILL_ modify on-disk contents!
msg "
##### Testing auto-update capability #####"
cd $SRC_TMP
#shellcheck disable=SC2154
cat >main.sh<< EOF
#!/bin/bash

source /etc/automation_environment  # defines AUTOMATION_LIB_PATH
source "$AUTOMATION_LIB_PATH/common_lib.sh"
source "$AUTOMATION_LIB_PATH/autoupdate.sh"
EOF
chmod +x main.sh

# Expect the real main.sh to bark one of two error messages
# and exit non-zero.
EXP_RX1="Must.be.called.with.exactly.two.arguments"
EXP_RX2="does.not.appear.to.be.the.root.of.a.git.repo"
if output=$(env BUILDPUSHAUTOUPDATED=0 ./main.sh 2>&1); then
    die "Fail.  Expected main.sh to exit non-zero"
else
    if [[ "$output" =~ $EXP_RX1 ]] || [[ "$output" =~ $EXP_RX2 ]]; then
        echo "PASS"
    else
        die "Fail.  Expecting match to '$EXP_RX1' or '$EXP_RX2', got:
$output"
    fi
fi
