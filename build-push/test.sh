

# DO NOT USE - This script is intended to be called by the Cirrus-CI
# `test_build-push` task.  It is not intended to be used otherwise
# and may cause harm.  It's purpose is to confirm the 'main.sh' script
# behaves in an expected way, given a local test repository as input.

set -e
SCRIPT_DIRPATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
source $SCRIPT_DIRPATH/../lib.sh

req_env_vars CIRRUS_CI

# Architectures to test with (golang standard names)
TESTARCHES="amd64 arm64"
# main.sh is sensitive to this value
ARCHES=$(tr " " ","<<<"$TESTARCHES")
export ARCHES
# Contrived "version" for testing purposes
FAKE_VERSION=$RANDOM
# Contrived source repository for testing
SRC_TMP=$(mktemp -p '' -d tmp-build-push-test-XXXX)
# Do not change, main.sh is sensitive to the 'testing' name
TEST_FQIN=example.com/testing/stable
# Stable build should result in manifest list tagged this
TEST_FQIN2=example.com/containers/testing

trap "rm -rf $SRC_TMP" EXIT

# main.sh expects $PWD to be a git repository.
msg "Constructing local test repository"
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
echo "build-push-test version $FAKE_VERSION" | tee "FAKE_VERSION"
cat <<EOF | tee "Containerfile"
FROM registry.fedoraproject.org/fedora:latest
ADD /FAKE_VERSION /
RUN dnf install -y iputils
EOF
cd $SRC_TMP/testing
git add --all
git commit -m 'test repo initial commit'

msg "Building test image '$TEST_FQIN' (in debug/dry-run mode)"
buildah --version
export DRYRUN=1  # Force main.sh not to push anything
req_env_vars ARCHES DRYRUN
# main.sh is sensitive to 'testing' value.
# also confirms main.sh is on $PATH
env DEBUG=1 main.sh git://testing contrib/testimage/stable

# Because this is a 'stable' image, verify that main.sh will properly
# version-tagged both FQINs.  No need to check 'latest'.
msg "Testing 'stable' images tagged '$FAKE_VERSION' for arches $TESTARCHES"
podman --version
req_env_vars TESTARCHES FAKE_VERSION TEST_FQIN TEST_FQIN2
for _fqin in $TEST_FQIN $TEST_FQIN2; do
    for _arch in $TESTARCHES; do
        # As of podman 3.4.4, the --arch=$arch argument will cause failures
        # looking up the image in local storage.  This bug is fixed in later
        # versions.  For now, query the manifest directly for the image sha256.
        _q='.manifests[] | select(.platform.architecture == "'"$_arch"'") | .digest'
        _s=$(podman manifest inspect $_fqin:$FAKE_VERSION | jq -r "$_q")
        msg "Found '$_arch' in manifest-list $_fqin:$FAKE_VERSION as digest $_s"
        if [[ -z "$_s" ]]; then
            die "Failed to get sha256 for FQIN '$_fqin:$FAKE_VERSION' ($_arch)"
        fi
        msg "Testing container can ping localhost"
        showrun podman run -i --rm "$_fqin@$_s" ping -q -c 1 127.0.0.1

        #TODO: Test org.opencontainers.image.source value
        #TODO: fails, returns null for some reason
        #msg "Confirming version-label matches tag"
        #_q='.[0].Labels."org.opencontainers.image.version"'
        #_v=$(podman image inspect "$_fqin@$_s" | jq -r "$_q")
        #showrun test $_v -eq $FAKE_VERSION
    done
done
