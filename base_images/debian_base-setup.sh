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

# TODO: Workaround forward-incompatible change in grub scripts.
# Without this, updating to the SID kernel will fail with
# "version_find_latest" in error logs. Something to do with
# gcloud assuming a wrong version of grub.
#
# 2023-11-16 before today, solution was to upgrade grub-common; as of
# today this is failing with a dependency error. Current solution today
# is now to create a version_find_latest script; grub will find and use this.
#
# This will probably be necessary until debian 13 becomes stable.
# At which time some new kludge will be necessary.
#
# FIXME: 2024-01-02: Bumped the timebomb expiration date because it's
#        too hard to find out if it's fixed or not
#        2024-01-25: again, and 02-26 again and 03-20 again
timebomb 20240330 "workaround for updating debian 12 to 13"
$SUDO tee /usr/bin/version_find_latest <<"EOF"
#!/bin/bash
#
# Grabbed from /usr/share/grub/grub-mkconfig_lib on f38
#
version_sort ()
{
  case $version_sort_sort_has_v in
    yes)
      LC_ALL=C sort -V;;
    no)
      LC_ALL=C sort -n;;
    *)
      if sort -V </dev/null > /dev/null 2>&1; then
        version_sort_sort_has_v=yes
    LC_ALL=C sort -V
      else
        version_sort_sort_has_v=no
        LC_ALL=C sort -n
      fi;;
   esac
}

version_test_numeric ()
{
  version_test_numeric_a="$1"
  version_test_numeric_cmp="$2"
  version_test_numeric_b="$3"
  if [ "$version_test_numeric_a" = "$version_test_numeric_b" ] ; then
    case "$version_test_numeric_cmp" in
      ge|eq|le) return 0 ;;
      gt|lt) return 1 ;;
    esac
  fi
  if [ "$version_test_numeric_cmp" = "lt" ] ; then
    version_test_numeric_c="$version_test_numeric_a"
    version_test_numeric_a="$version_test_numeric_b"
    version_test_numeric_b="$version_test_numeric_c"
  fi
  if (echo "$version_test_numeric_a" ; echo "$version_test_numeric_b") | version_sort | head -n 1 | grep -qx "$version_test_numeric_b" ; then
    return 0
  else
    return 1
  fi
}

version_test_gt ()
{
  version_test_gt_a="`echo "$1" | sed -e "s/[^-]*-//"`"
  version_test_gt_b="`echo "$2" | sed -e "s/[^-]*-//"`"
  version_test_gt_cmp=gt
  if [ "x$version_test_gt_b" = "x" ] ; then
    return 0
  fi
  case "$version_test_gt_a:$version_test_gt_b" in
    *.old:*.old) ;;
    *.old:*) version_test_gt_a="`echo "$version_test_gt_a" | sed -e 's/\.old$//'`" ; version_test_gt_cmp=gt ;;
    *:*.old) version_test_gt_b="`echo "$version_test_gt_b" | sed -e 's/\.old$//'`" ; version_test_gt_cmp=ge ;;
    *-rescue*:*-rescue*) ;;
    *?debug:*?debug) ;;
    *-rescue*:*?debug) return 1 ;;
    *?debug:*-rescue*) return 0 ;;
    *-rescue*:*) return 1 ;;
    *:*-rescue*) return 0 ;;
    *?debug:*) return 1 ;;
    *:*?debug) return 0 ;;
  esac
  version_test_numeric "$version_test_gt_a" "$version_test_gt_cmp" "$version_test_gt_b"
  return "$?"
}


version_find_latest_a=""
for i in "$@" ; do
  if version_test_gt "$i" "$version_find_latest_a" ; then
    version_find_latest_a="$i"
  fi
done

echo "$version_find_latest_a"
EOF
$SUDO chmod 755 /usr/bin/version_find_latest

# 2024-01-02 between 2023-12 and now, debian got tar-1.35+dfsg-2
# which has the horrible duplicate-path bug:
#     https://github.com/containers/podman/issues/19407
#     https://bugzilla.redhat.com/show_bug.cgi?id=2230127
# 2024-01-25 dfsg-3 also has the bug
timebomb 20240330 "prevent us from getting broken tar-1.35+dfsg-3"
( set -x; $SUDO apt-mark hold tar; )

echo "Upgrading to SID"
( set -x; $SUDO apt-get -q -y full-upgrade; )
echo "Installing basic, necessary packages."
( set -x; $SUDO apt-get -q -y install "${PKGS[@]}"; )

# compatibility / usefullness of all automated scripting (which is bash-centric)
( set -x; $SUDO DEBCONF_DB_OVERRIDE='File{'$SCRIPT_DIRPATH/no_dash.dat'}' \
    dpkg-reconfigure dash; )

# Ref: https://wiki.debian.org/DebianReleases
# CI automation needs a *sortable* OS version/release number to select/perform/apply
# runtime configuration and workarounds.  Since switching to Unstable/SID, a
# numeric release version is not available. While an imperfect solution,
# base an artificial version off the 'base-files' package version, right-padded with
# zeros to ensure sortability (i.e. "12.02" < "12.13").
base_files_version=$(dpkg -s base-files | awk '/Version:/{print $2}')
base_major=$(cut -d. -f 1 <<<"$base_files_version")
base_minor=$(cut -d. -f 2 <<<"$base_files_version")
sortable_version=$(printf "%02d.%02d" $base_major $base_minor)
echo "WARN: This is NOT an official version number.  It's for CI-automation purposes only."
( set -x; echo "VERSION_ID=\"$sortable_version\"" | \
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
