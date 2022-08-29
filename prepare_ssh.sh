#!/usr/bin/env bash

# edit the hostname
hostname=plapperkasten1
# edit the remote user if you are not using ubuntu server
remoteuser=ubuntu

if [[ -z $(grep -F "$hostname" "/home/$USER/.ssh/known_hosts") ]]
then
  ssh-keygen -f "/home/$USER/.ssh/known_hosts" -R "$hostname"
fi

[[ ! -f /home/$USER/.ssh/$hostname ]] &&
  ssh-keygen -b 4096 -f /home/$USER/.ssh/$hostname

ssh-copy-id -i /home/$USER/.ssh/$hostname $remoteuser@$hostname
