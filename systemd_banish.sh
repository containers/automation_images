#!/bin/bash

# This is intended to be executed stand-alone, on a Fedora or Debian VM
# by automation.  Alternatively, it may be executed with the '--list'
# option to return the list of systemd units defined for disablement
# (useful for testing).

set +e  # Not all of these exist on every platform

# Setting noninteractive is critical, apt-get can hang w/o it.
if [[ "$UID" -ne 0 ]]; then
    export SUDO="sudo env DEBIAN_FRONTEND=noninteractive"
fi

EVIL_UNITS="cron crond atd apt-daily-upgrade apt-daily fstrim motd-news systemd-tmpfiles-clean update-notifier-download mlocate-updatedb"

if [[ "$1" == "--list" ]]
then
    echo "$EVIL_UNITS"
    exit 0
fi

echo "Disabling periodic services that could destabilize automation:"
for unit in $EVIL_UNITS
do
    echo "Banishing $unit (ignoring errors)"
    (
        $SUDO systemctl stop $unit
        $SUDO systemctl disable $unit
        $SUDO systemctl disable $unit.timer
        $SUDO systemctl mask $unit
        $SUDO systemctl mask $unit.timer
    ) &> /dev/null
done

# Sigh, for Debian the above isn't enough.  There are also periodic apt jobs.
EAAD="/etc/apt/apt.conf.d"
PERIODIC_APT_RE='^(APT::Periodic::.+")1"\;'
if [[ -d "$EAAD" ]]; then
    echo "Disabling all periodic packaging activity"
    for filename in $($SUDO ls -1 $EAAD); do \
        echo "Checking/Patching $filename"
        $SUDO sed -i -r -e "s/$PERIODIC_APT_RE/"'\10"\;/' "$EAAD/$filename"; done
fi

# Early 2023: https://github.com/containers/podman/issues/16973
#
# We see countless instances of "lookup cdn03.quay.io" flakes.
# Disabling the systemd resolver (Podman #17505) seems to have almost
# eliminated those -- the exceptions are early-on steps that run
# before that happens.
#
# Opinions differ on the merits of systemd-resolve, but the fact is
# it breaks our CI testing. Here we disable it for all VMs.
# shellcheck disable=SC2154
if ! ((CONTAINER)); then
    nsswitch=/etc/authselect/nsswitch.conf
    if [[ -e $nsswitch ]]; then
        if grep -q -E 'hosts:.*resolve' $nsswitch; then
            echo "Disabling systemd-resolved"
            $SUDO sed -i -e 's/^\(hosts: *\).*/\1files dns myhostname/' $nsswitch
            $SUDO systemctl disable --now systemd-resolved
            $SUDO rm -f /etc/resolv.conf

            # NetworkManager may already be running, or it may not....
            $SUDO systemctl start NetworkManager
            sleep 1
            $SUDO systemctl restart NetworkManager

            # ...and it may create resolv.conf upon start/restart, or it
            # may not. Keep restarting until it does. (Yes, I realize
            # this is cargocult thinking. Don't care. Not worth the effort
            # to diagnose and solve properly.)
            retries=10
            while ! test -e /etc/resolv.conf;do
                retries=$((retries - 1))
                if [[ $retries -eq 0 ]]; then
                    die "Timed out waiting for resolv.conf"
                fi
                $SUDO systemctl restart NetworkManager
                sleep 5
            done
        fi
    fi
fi
