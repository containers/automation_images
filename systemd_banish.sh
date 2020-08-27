#!/bin/bash

# This is intended to be executed stand-alone, on a Fedora or Ubuntu VM
# by automation.  Alternatively, it may be executed with the '--list'
# option to return the list of systemd units defined for disablement
# (useful for testing).

set +e  # Not all of these exist on every platform

SUDO=""
[[ "$UID" -eq 0 ]] || \
    SUDO="sudo"

EVIL_UNITS="cron crond atd apt-daily-upgrade apt-daily fstrim motd-news systemd-tmpfiles-clean"

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

# Sigh, for Ubuntu the above isn't enough.  There are also periodic apt jobs.
EAAD="/etc/apt/apt.conf.d"
PERIODIC_APT_RE='^(APT::Periodic::.+")1"\;'
if [[ -d "$EAAD" ]]; then
    echo "Disabling all periodic packaging activity"
    for filename in $($SUDO ls -1 $EAAD); do \
        echo "Checking/Patching $filename"
        $SUDO sed -i -r -e "s/$PERIODIC_APT_RE/"'\10"\;/' "$EAAD/$filename"; done
fi
