#!/usr/bin/env bash

# do not change these instead use `config.conf`
export OS_DEBIAN="debian"
export OS_UBUNTU="ubuntu"
export COUNTRY_GERMANY="DE"

setup_for="$OS_DEBIAN"
unmount=1
device=""
hostname=""
plk_user=""
plk_password=""
wlan_ssid=""
wlan_password=""
wlan_country=""
display=""
soundcard=""

[[ -f config.conf ]] &&
    source config.conf

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

if [[ $setup_for == "$OS_DEBIAN" && -z $plk_user || -z $plk_password ]]
then
    echo -e "----------------------------------------------------"
    echo -e "Setup User"

    echo -e "User: $plk_user"
    while [[ ! $plk_user =~ ^[a-zA-Z0-9._]+$ ]]
    do
        echo -en "\e[1A\e[K"
        read -p "User: " plk_user
    done
    echo -e "Password (a-zA-Z0-9._+#+*:): $plk_password"
    while [[ ! $plk_password =~ ^[a-zA-Z0-9._#+*:]+$ ]]
    do
        echo -en "\e[1A\e[K"
        read -p "Password: " plk_password
    done
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
    #exit 1
fi

[[ ! -f "$system" ]] &&
  mkdir -p "$system"

if ! sudo mount "$system_dev" "$system"
then
    echo -e "could not mount $system_dev"
    #exit 1
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
# configure a user


if [[ "$setup_for" == "$OS_DEBIAN" ]]
then
    echo -e "configuring user: $plk_user with \"$plk_password\""
    sudo echo -e "$plk_user:$(openssl passwd -6 $plk_password)" > "$boot/userconf.txt"
    echo -e "user configured"
fi

################################################################################
# configure wlan

echo -e "configuring wlan: $wlan_ssid"
if [[ -z $(grep -F "# plk_wlan" "$boot/network-config") && ! -z $wlan_ssid ]]
then
    export wlan_ssid
    export wlan_password
    export wlan_country
    if [[ "$setup_for" == "$OS_DEBIAN" ]]
    then
        envsubst '$wlan_ssid $wlan_password $wlan_country' < "$cfg/wpa_supplicant" > wlan_tmp
        sudo cat wlan_tmp > "$boot/wpa_supplicant.conf"
        sudo chmod 600 "$boot/wpa_supplicant.conf"
    elif [[ "$setup_for" == "$OS_UBUNTU" ]]
    then
        envsubst '$wlan_ssid $wlan_password' < "$cfg/wlan" > wlan_tmp
        sudo cat wlan_tmp > "$boot/network-config"
        sudo chmod 600 "$boot/network-config"
    fi
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
# enable ssh

# ssh needs to be enabled on Raspbian OS Lite
# but not on ubuntu server
if [[ "$setup_for" == "$OS_DEBIAN" ]]
then
    echo -e "enabling ssh"
    sudo touch "$boot/ssh"
    echo -e "ssh enabled"
fi

################################################################################
# create paths

echo -e "creating paths"
sudo mkdir -p "$system/data/plapperkasten/Media/Audiobooks/"
sudo mkdir -p "$system/data/plapperkasten/Media/Music/"
sudo mkdir -p "$system/data/plapperkasten/Playlists/"
sudo mkdir -p "$system/data/plapperkasten/MPD/"
echo -e "paths created"

################################################################################
# create poweroff script

sudo tee $system/lib/systemd/system-shutdown/plapperkasten_poweroff.shutdown <<EOF
#! /bin/sh
# https://newbedev.com/how-to-run-a-script-with-systemd-right-before-shutdown
# \$1 will be either "halt", "poweroff", "reboot" or "kexec"
poweroff_pin=4
case "\$1" in
    poweroff|halt)
        # wait for other processes to finish so this happens last
        /bin/sleep 0.5
        # this might be expressed a little more elegantly
        /bin/gpioset -l -Bpull-down gpiochip0 $poweroff_pin=1
        ;;
esac
EOF
sudo chmod +x $system/lib/systemd/system-shutdown/plapperkasten_poweroff.shutdown

################################################################################
# copy plapperkasten files to the new system

echo -e "moving setup files to new system"
sudo mkdir -p "$system/data/plapperkasten/Setup"
sudo cp -r ./templates "$system/data/plapperkasten/Setup/"
sudo cp -r ./README.md "$system/data/plapperkasten/Setup/"
sudo cp -r ./Makefile "$system/data/plapperkasten/Setup/"
echo -e "setup files can be found under $system/data/plapperkasten/Setup"

################################################################################
# finish

sleep 1

if [[ "$unmount" -gt 0 ]]
then
    echo -e "unmounting partitions"
    sudo umount "$boot"
    sudo umount "$system"
fi

echo -e "Boot device with sd-card inserted."
echo -e "Run ./prepare_ssh.sh $hostname $plk_user"
echo -e "On $hostname go to /data/plapperkasten/Setup and run \`make\` and \`sudo make install\`"
read -p "Press [ENTER] to continue"
exit 0
