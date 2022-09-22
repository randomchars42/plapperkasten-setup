#!/usr/bin/env bash

device=""
hostname=""
wlan_ssid="WLAN-Kabel-2"
wlan_password=""
display=""
soundcard=""

################################################################################
# do not edit below

cfg="./system_configurations"
boot="./mnt/system-boot"
boot_cfg="$boot/config.txt"
system="./mnt/writeable"

################################################################################
# function definitions

# let the user choose from a range of options
# the default choice can be specified by setting the global variable
# `choice`
# the result will be stored in the globale variable `choice`
# example:
# > choice=b
# > items=(a b c d)
# > display_choice ${items[*]}
choice=""
function display_choice {
    [[ $# -eq 0 ]] &&
        echo -e "missing arguments" &&
        return 1

    local default_number=-1

    echo -e "Please choose (* default): "
    for (( c=1; c<="$#"; c++ ))
    do
        if [[ ${!c} == "$choice" ]]
        then
            echo -e " * $c: ${!c}"
            default_number="$c"
        else
            echo -e "   $c: ${!c}"
        fi
    done

    local number=-1

    echo -e "Number:"

    while [[ $number -lt 1 || $number -gt "$#" ]]
    do
        echo -en "\e[1A\e[K"
        read -p "Number: " number
        if [[ -z "$number" && $default_number -gt -1 ]]
        then
            number=$default_number
        fi
    done

    choice=${!number}

    echo -e "Your choice: $choice"
    return 0
}

# copy the snippets the user has chosen with `display_choice`
function configure_hardware {
    [[ -z "$1" ]] &&
        echo -e "malshaped call to configure_hardware" &&
        return 1
    [[ ! -f "$1" ]] &&
        echo -e "no such configuration (\"$1\")" &&
        return 1

    # nothing to configure
    [[ "$1" == "None" ]] &&
        return 0

    local name="$(basename $1)"

    echo -e "configuring $name:"
    if [[ -z $(grep -F "# plk_$name" "$boot_cfg") ]]
    then
        sudo cat "$1" >> "$boot_cfg"
        echo -e "$name configured"
    else
        echo -e "$name already configured"
    fi

    return 0
}

################################################################################
# check root

if [ "$(whoami)" != "root" ]; then
    echo "Please run this script as root."
    exit 1
fi

################################################################################
# get user's choices

if [[ -z $device ]]
then
    echo -e "----------------------------------------------------"

    device_default="d"

    echo -e "Set device (default: \"$device_default\"): "
    echo -e "Device /dev/sdX:"

    while [[ ! $device =~ ^[a-z]{1}$ ]]
    do
        echo -en "\e[1A\e[K"
        read -p "Device /dev/sdX:" device
        if [[ -z "$device" ]]
        then
            device="$device_default"
        fi
    done

    echo -e "Setting device: $device"

    echo
fi

if [[ -z $hostname ]]
then
    echo -e "----------------------------------------------------"

    hostname_default="plapperkasten1"

    echo -e "Set hostname (default: \"$hostname_default\"): "
    echo -e "Hostname:"

    while [[ ! $hostname =~ ^[a-zA-Z0-9._]+$ ]]
    do
        echo -en "\e[1A\e[K"
        read -p "Hostname: " hostname
        if [[ -z "$hostname" ]]
        then
            hostname="$hostname_default"
        fi
    done

    echo -e "Setting hostname: $hostname"

    echo
fi

if [[ -z $wlan_ssid || -z $wlan_password ]]
then
    echo -e "----------------------------------------------------"
    echo -e "Setup WLAN?"

    [[ -z $wlan_ssid ]] &&
        read -p "WLAN name (SSID) - leave empty to skip:" wlan_ssid
    [[ ! -z $wlan_ssid ]] &&
        read -s -p "WLAN password:" wlan_password
    echo
fi

if [[ -z $display ]]
then
    echo -e "----------------------------------------------------"
    echo -e "Include display?"
    displays="$cfg/display_*"
    options=(None $displays)
    choice=None
    display_choice ${options[*]}
    display="$choice"
    echo
fi

if [[ -z $soundcard ]]
then
    echo -e "----------------------------------------------------"
    echo -e "Include soundcard?"
    soundcards="$cfg/soundcard_*"
    options=(None $soundcards)
    choice=None
    display_choice ${options[*]}
    soundcard="$choice"
    echo
fi

echo -e "----------------------------------------------------"
echo -e "----------------------------------------------------"


################################################################################
# mount partition

boot_dev="/dev/sd${device}1"
system_dev="/dev/sd${device}2"

echo -e "mounting partitions"

[[ ! -f "$boot" ]] &&
  mkdir -p "$boot"

if ! sudo mount "$boot_dev" "$boot"
then
    echo -e "could not mount $bootdev"
fi

[[ ! -f "$system" ]] &&
  mkdir -p "$system"

if ! sudo mount "$system_dev" "$system"
then
    echo -e "could not mount $system_dev"
fi

################################################################################
# configure hostname

echo -e "configuring hostname: $hostname"
if [[ -z $(grep -F "$hostname" "$system/etc/hostname") ]]
then
    sudo echo "$hostname" > "$system/etc/hostname"
    echo -e "hostname configured"
else
    echo -e "hostname already configured"
fi

################################################################################
# configure wlan

echo -e "configuring wlan: $wlan_ssid"
if [[ -z $(grep -F "# plk_wlan" "$boot/network-config") && ! -z $wlan_ssid ]]
then
    export wlan_ssid
    export wlan_password
    envsubst '$wlan_ssid $wlan_password' < "$cfg/wlan" > wlan_tmp
    sudo cat wlan_tmp > "$boot/network-config"
    rm wlan_tmp
    echo -e "wlan configured"
else
    echo -e "wlan already configured"
fi

################################################################################
# configure hardware

configure_hardware "$soundcard"
configure_hardware "$display"

################################################################################
# create paths

echo -e "creating paths"
sudo mkdir -p "$system/data/ebox/Media/Audiobooks/"
sudo mkdir -p "$system/data/ebox/Media/Music/"
sudo mkdir -p "$system/data/ebox/Playlists/"
sudo mkdir -p "$system/data/ebox/MPD/"
echo -e "paths created"

################################################################################
# create poweroff script

sudo tee -a $system/lib/systemd/system-shutdown/plapperkasten_poweroff.shutdown <<EOF
#! /bin/sh
# https://newbedev.com/how-to-run-a-script-with-systemd-right-before-shutdown
# $1 will be either "halt", "poweroff", "reboot" or "kexec"
poweroff_pin=4
case "$1" in
    poweroff|halt)
        # wait for other processes to finish so this happens last
        /bin/sleep 0.5
        # this might be expressed a little more elegantly
        /bin/gpioset -l -Bpull-down gpiochip0 $poweroff_pin=1
        ;;
esac
EOF
sudo chmod +x /lib/systemd/system-shutdown/plapperkasten_poweroff.shutdown

################################################################################
# finish

sleep 1

echo -e "unmounting partitions"
sudo umount "$boot"
sudo umount "$system"

echo -e "Boot device with sd-card inserted (two times if WLAN should be used)."
echo -e "Run ./prepare_ssh.sh"
read -p "Press [ENTER] to continue"
exit 0
