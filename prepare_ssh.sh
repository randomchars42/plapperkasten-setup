#!/usr/bin/env bash

[[ -f config.conf ]] &&
    source config.conf

[[ -z $hostname ]] &&
    read -p "Hostname: " hostname
[[ -r $plk_user ]] &&
    read -p "User: " plk_user

if [[ -z $(grep -F "$hostname" "/home/$USER/.ssh/known_hosts") ]]
then
  ssh-keygen -f "/home/$USER/.ssh/known_hosts" -R "$hostname"
fi

[[ ! -f /home/$USER/.ssh/$hostname ]] &&
  ssh-keygen -b 4096 -f /home/$USER/.ssh/$hostname

ssh-copy-id -i /home/$USER/.ssh/$hostname $plk_user@$hostname
