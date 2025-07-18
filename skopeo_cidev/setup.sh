

# This script is used by the Containerfile when building an image.
# It should NEVER ever (EVER!) be used under any other circumstances
# (nor set as executable).

set -e

declare -a req_vars
req_vars=(\
    REG_REPO
    REG_COMMIT_SCHEMA1
    OSO_REPO
    OSO_TAG
)
for req_var in "${req_vars[@]}"; do
    if [[ -z "${!req_var}" ]]; then
        echo "ERROR: Required variable \$$req_var is unset or empty."
        exit 1
    fi
done

GOPATH=$(mktemp -d -p '' ".tmp_$(basename ${BASH_SOURCE[0]})_XXXXXXXX")
REG_GOSRC="$GOPATH/src/github.com/docker/distribution" \
OSO_GOSRC="$GOPATH/src/github.com/openshift/origin"

# All golang code built here pre-dates support of go modules
export GO111MODULE=off

# Workaround unnecessary swap-enabling shenanagains in openshift-origin build
export OS_BUILD_SWAP_DISABLE=1

# Make debugging easier
set -x

# This comes in from the Containerfile
# shellcheck disable=SC2154
git clone "$REG_REPO" "$REG_GOSRC"
cd "$REG_GOSRC"

# Don't pollute the environment
(
    # This is required to be set like this by the build system
    export GOPATH="$PWD/Godeps/_workspace:$GOPATH"
    # This comes in from the Containerfile
    # shellcheck disable=SC2154
    git checkout -q "$REG_COMMIT_SCHEMA1"
    go build -o /usr/local/bin/registry-v2-schema1 \
        github.com/docker/distribution/cmd/registry
)

# These come in from the Containerfile
# shellcheck disable=SC2154
git clone --depth 1 -b "$OSO_TAG" "$OSO_REPO" "$OSO_GOSRC"
cd "$OSO_GOSRC"

# Edit out a "go < 1.5" check which works incorrectly with go >= 1.10.
sed -i -e 's/\[\[ "\${go_version\[2]}" < "go1.5" ]]/false/' ./hack/common.sh

# Fix a bug in 'options' line processing of resolv.conf when an option is
# 8 characters long.  This can happen if/when systemd-resolved adds 'trust-ad'.
sed -i  '/== "attempts:"/s/ 8 / 9 /' vendor/github.com/miekg/dns/clientconfig.go

# Backport https://github.com/ugorji/go/commit/8286c2dc986535d23e3fad8d3e816b9dd1e5aea6
# Go ≥ 1.22 panics with a base64 encoding using duplicated characters.
sed -i -e 's,"encoding/base64","encoding/base32", ; s,base64.NewEncoding("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789__"),base32.NewEncoding("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"),' vendor/github.com/ugorji/go/codec/gen.go

make build
make all WHAT=cmd/dockerregistry
cp -a ./_output/local/bin/linux/*/* /usr/local/bin/
cp ./images/dockerregistry/config.yml /atomic-registry-config.yml
mkdir /registry

# When script unsuccessful, leave this behind for debugging
# Removing these two items _significantly_ reduces the image size.
rm -rf $GOPATH $(go env GOCACHE)
