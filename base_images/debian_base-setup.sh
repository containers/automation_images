#!/bin/bash

# This script is intended to be run by packer, inside an Debian VM.
# It's purpose is to configure the VM for importing into google cloud,
# so that it will boot in GCE and be accessable for further use.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# Run as quickly as possible after boot
/bin/bash $REPO_DIRPATH/systemd_banish.sh

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

echo "Switch sources to Debian Unstable (SID)"
cat << EOF | $SUDO tee /etc/apt/sources.list
deb http://deb.debian.org/debian/ unstable main
deb-src http://deb.debian.org/debian/ unstable main
EOF

declare -a PKGS
PKGS=( \
    coreutils
    curl
    cloud-init
    gawk
    openssh-client
    openssh-server
    rng-tools5
    software-properties-common
)

echo "Updating package source lists"
( set -x; $SUDO apt-get -q -y update; )

# Only deps for automation tooling
( set -x; $SUDO apt-get -q -y install git )
install_automation_tooling
# Ensure automation library is loaded
source "$REPO_DIRPATH/lib.sh"

# 2024-01-02 found debian 13 tar 1.35+dfsg-2
# which has the horrible duplicate-path bug:
#     https://github.com/containers/podman/issues/19407
#     https://bugzilla.redhat.com/show_bug.cgi?id=2230127
# 2024-01-25 dfsg-3 also has the bug
# 2024-05-01 trixy still has 1.35+dfsg-3
timebomb 20240801 "prevent us from getting broken tar-1.35+dfsg-3"
$SUDO tee /etc/apt/preferences.d/$(date +%Y%m%d)-tar <<EOF
Package: tar
Pin: version 1.35+dfsg-[23]
Pin-Priority: -1
EOF

# 2024-05-28 Cirrus CI failures with “Agent is not responding!”
# https://github.com/containers/podman/pull/22820#issuecomment-2135385145
timebomb 20240615 "don't update systemd to a version which requires CGroups v2"
$SUDO tee /etc/apt/preferences.d/$(date +%Y%m%d)-systemd <<EOF
Package: systemd systemd-timesyncd systemd-resolved systemd-sysv libsystemd0 libsystemd-shared libudev1
Pin: version 255.5-1
Pin-Priority: 900
EOF

# Workaround 12->13 forward-incompatible change in grub scripts.
# Without this, updating to the SID kernel may fail.
echo "Upgrading grub-common"
( set -x; $SUDO apt-get -q -y upgrade grub-common; )

echo "Upgrading to SID"
( set -x; $SUDO apt-get -q -y full-upgrade; )
echo "Installing basic, necessary packages."
( set -x; $SUDO apt-get -q -y install "${PKGS[@]}"; )

# compatibility / usefullness of all automated scripting (which is bash-centric)
( set -x; $SUDO DEBCONF_DB_OVERRIDE='File{'$SCRIPT_DIRPATH/no_dash.dat'}' \
    dpkg-reconfigure dash; )

# Ref: https://wiki.debian.org/DebianReleases
# CI automation needs an OS version/release number for a variety of uses.
# However, After switching to Unstable/SID, the value from the usual source
# is not available. Simply use the value passed through packer by the Makefile.
req_env_vars DEBIAN_RELEASE
# shellcheck disable=SC2154
warn "Setting '$DEBIAN_RELEASE' as the release number for CI-automation purposes."
( set -x; echo "VERSION_ID=\"$DEBIAN_RELEASE\"" | \
    $SUDO tee -a /etc/os-release; )

if ! ((CONTAINER)); then
    custom_cloud_init
    ( set -x; $SUDO systemctl enable rngd; )

    # Cloud-config fails to enable this for some reason or another
    ( set -x; $SUDO sed -i -r \
      -e 's/^PermitRootLogin no/PermitRootLogin prohibit-password/' \
      /etc/ssh/sshd_config; )
fi

finalize
