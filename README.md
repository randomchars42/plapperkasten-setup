# Setup guide for `plapperkasten` on a Raspberry Pi

## Goals

* Setup a Raspberry Pi as a server to play music.
* RFID cards or chips are used to load a predefined playlist or folder
  containing music.
* Playback and volume are controlled via buttons or RFID cards or chips

For this we will use [plapperkasten](https://github.com/randomchars42/plapperkasten).

## Notes

* The setup procedure is described for **Debian Bulsseye** though
  it should work for **Ubuntu 21.10 Server** (or newer) as well.
* This guide does a *headless* setup (meaning you won't attach a display or
  keyboard to your Raspberry Pi) so you are going to need a patch (LAN) cable to
  connect your Raspberry Pi with the network (WLAN?) router you have or your
  computer.

## Exemplary hardware

* Raspberry Pi 3b
* any suitably large (and fast) microSD card
* HIFIBerry DAC
* Pimoroni OnOffShim
* AMAO RFID Reader 13.56 MHz
* a couple of buttons to control volume, play, stop, skip forwards / backwards,
  ... are attached to the GPIO pins

In theory soldering could be avoided though it might make life easier.

## On your local machine

### Installation of the system image

To install Ubuntu or Debian plug the microSD card into your computer. The
easiest way is to use the RPI imager (<https://www.raspberrypi.com/software/>)

### Configure SSH access

* edit `prepare_ssh.sh` and run:

```bash
chmod +x prepare_ssh.sh
./prepare_ssh.sh
```

* or manually:

```bash
# edit the hostname
hostname=plapperkasten1
# edit the remote user if you are not using Debian Bullseye
remoteuser=plapperkasten

if [[ -z $(grep -F "$hostname" "/home/$USER/.ssh/known_hosts") ]]
then
  ssh-keygen -f "/home/$USER/.ssh/known_hosts" -R "$hostname"
fi

[[ ! -f /home/$USER/.ssh/$hostname ]] &&
  ssh-keygen -b 4096 -f /home/$USER/.ssh/$hostname

ssh-copy-id -i /home/$USER/.ssh/$hostname $remoteuser@$hostname
```

## On the remote machine (your new plapperkasten)

* (login remotely via ssh ;) )
* install prerequisites for building python:

```bash
sudo apt-get update
sudo apt-get install build-essential libssl-dev zlib1g-dev \
libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev \
liblzma-dev git

# optional packages:
# `mpd` and `mpc` for media playback via mpd (plugin `mpdclient`)
# `alsa-utils` for volume controll / switching cards (plugin `volumealsa`)
# `python3-lgpio` for userland access to GPIO pins (plugin `inputgpiod`)
sudo apt install mpd mpc alsa-utils python3-libgpiod
```

### Short version

* run:

```bash
# clone this repository
git clone git@github.com:randomchars42/plapperkasten-setup.git
cd plapperkasten-setup
# install pyenv, python, pipx and plapperkasten
make
# install plapperkasten.service, shutdown routine and udev rules
sudo make install
```

* restart

### Long version

This version is equivalent to `make && sudo make install`

```bash
# this is where everything will be installed
pk_app_path="/data/plapperkasten/plapperkasten"
# use this python version
pk_python_version="3.10.4"

# define some variables for convenience
pk_name=plapperkasten
pk_pyenv_path=${pk_app_path}/pyenv
pk_pyenv=${pk_pyenv_path}/bin/pyenv
pk_pipx_home_path=${pk_app_path/pipx}
# everytime we call python use the PYENV_ROOT
pk_python=PYENV_ROOT=${pk_pyenv_path} ${pk_pyenv_path}/versions/${pk_python_version}/bin/python
pk_pip=${pk_python} -m pip
pk_pipx=${pk_python} -m pipx
pk_app=${pk_pipx_home_path}/venvs/${pk_name}/bin/${pk_name}

mkdir -p ${pk_app_path}

# install pyenv to provide a custom and local python version
git clone https://github.com/pyenv/pyenv.git "${pk_pyenv_path}"

# install python
# set PYENV_ROOT to correctly install packages
PYENV_ROOT=${pk_pyenv_path} ${pk_pyenv} install ${pk_python_version}

# install pipx to isolate plapperkasten
${pk_pip} install pipx

# install plapperkasten
PIPX_HOME=${pk_pipx_home_path} ${pk_pipx} install --system-site-packages ${pk_name}
```

#### Automatic startup of `plapperkasten`

```bash
# change user and group if not on Debian Bullseye after `plapperkasten-setup`
pk_user=plapperkasten
pk_group=plapperkasten
# this is where everything will be installed
pk_app_path="/data/plapperkasten/plapperkasten"
pk_name=plapperkasten
pk_pipx_home_path=${pk_app_path/pipx}
pk_app=${pk_pipx_home_path}/venvs/${pk_name}/bin/${pk_name}

sudo tee -a /etc/systemd/system/plapperkasten.service <<EOF
Description=start plapperkasten

[Service]
Type=simple
RemainAfterExit=yes
ExecStart=bash plapperkasten
User=${pk_user}
Group=${pk_group}

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable plapperkasten.service
sudo systemctl start plapperkasten.service
```

#### Create configuration files

```bash
# this is where everything will be installed
pk_app_config_path="~/.config/plapperkasten"

mkdir -p ${pk_app_config_path}

touch ${pk_app_config_path}/config.yaml
touch ${pk_app_config_path}/events.map
touch ${pk_app_config_path}/mpdclient_status.map
```

#### Configure ALSA in case you have a soundcard connected to the board

```bash
sudo mv /etc/asound.conf /etc/ascound.conf.bk
sudo tee /etc/asound.conf <<EOF
pcm.hifiberryMiniAmp {
    type softvol
    slave.pcm "plughw:1"
    control.name "Master"
    control.card 1
}
pcm.!default {
    type plug
    slave.pcm "hifiberryMiniAmp"
}
EOF
# reload ALSA
sudo alsactl restore
```

### Configure MPD

```bash
# change user and group if not on Debian Bullseye after `plapperkasten-setup`
pk_user=plapperkasten
pk_group=plapperkasten
# change path to where your data resides
pk_data_path=/data/plapperkasten

# make sure paths exist
mkdir -p ${pk_data_path}/Media
mkdir -p ${pk_data_path}/Playlists
mkdir -p ${pk_data_path}/MPD
sudo chown -r ${pk_user}:${pk_group} ${pk_data_path}

sudo mv /etc/alsa.conf /etc/alsa.conf.bk
sudo tee /etc/asound.conf <<EOF
music_directory         "${pk_data_path}/Media"
playlist_directory      "${pk_data_path}/Playlists"
db_file                 "${pk_data_path}/MPD/tag_cache"
log_file                "${pk_data_path}/MPD/mpd.log"
state_file              "${pk_data_path}/MPD/state"
sticker_file            "${pk_data_path}/MPD/sticker.sql"
user                    "${pk_user}"
group                   "audio"
bind_to_address         "any"
restore_paused          "yes"
port                    "6600"
replaygain              "auto"
volume_normalization    "yes"
filesystem_charset      "UTF-8"
input {
        plugin "curl"
}
audio_output {
        type            "alsa"
        name            "MPD"
        mixer_control   "Master"        # optional
}
playlist_plugin {
        name "m3u"
        enabled "true"
}
EOF
sudo systemctl restart mpd
```

#### Make sure the power is cut when using Pimoroni OnOffShim without software

The guys from Pimoroni ship an installer for their scripts so that OnOffShim
cuts the power supply after shutdown. This script might not be compatible
with Ubuntu Server.

In essence, this script pulls down GPIO 4 at the latest possible point in time -
right before shutdown is finished. This cuts the power supply without damaging
the machine.

Such a script has to be placed in: `/lib/systemd/system-shutdown/`

So we create a corresponding script:

```bash
sudo tee -a /lib/systemd/system-shutdown/plapperkasten_poweroff.shutdown <<EOF
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
sudo chmod +x /lib/systemd/system-shutdown/plapperkasten_poweroff.shutdown
```

#### Run plapperkasten as a non root user (accessing GPIO without root that is)

* create a file with the appropriate udev rules for accessing the gpio pins
  without being root - make sure to specify the appropriate user group:

```bash
# change user and group if not on Debian Bullseye after `plapperkasten-setup`
pk_group=ubuntu

sudo tee -a /etc/udev/rules.d/99-userdev_input.rules <<EOF
# make single pins / lines / events accessible
KERNEL=="event*", SUBSYSTEM=="input", GROUP="${pk_group}", MODE="660"
# make the gpiochips accessibel
KERNEL=="gpiochip*", SUBSYSTEM=="gpio", GROUP="${pk_group}", MODE="660"
EOF
```

* restart

### Upgrade

* run:

```bash
make upgrade
```

* or (long version):

```bash
# this is where everything will be installed
pk_app_path="/data/plapperkasten/plapperkasten"
# use this python version
pk_python_version="3.10.4"

# define some variables for convenience
pk_name=plapperkasten
pk_pyenv_path=${pk_app_path}/pyenv
pk_pyenv=${pk_pyenv_path}/bin/pyenv
pk_pipx_home_path=${pk_app_path/pipx}
# everytime we call python use the PYENV_ROOT
pk_python=PYENV_ROOT=${pk_pyenv_path} ${pk_pyenv_path}/versions/${pk_python_version}/bin/python
pk_pip=${pk_python} -m pip
pk_pipx=${pk_python} -m pipx
pk_app=${pk_pipx_home_path}/venvs/${pk_name}/bin/${pk_name}

# upgrade plapperkasten
PIPX_HOME=${pk_pipx_home_path} ${pk_pipx} upgrade ${pk_name}
```

### Uninstall

* run:

```bash
sudo make uninstall
```

* or (long version):

```bash
# this is where everything will be installed
pk_app_path="/data/plapperkasten/plapperkasten"
# use this python version
pk_python_version="3.10.4"

# define some variables for convenience
pk_name=plapperkasten
pk_pyenv_path=${pk_app_path}/pyenv
pk_pyenv=${pk_pyenv_path}/bin/pyenv
pk_pipx_home_path=${pk_app_path/pipx}
# everytime we call python use the PYENV_ROOT
pk_python=PYENV_ROOT=${pk_pyenv_path} ${pk_pyenv_path}/versions/${pk_python_version}/bin/python
pk_pip=${pk_python} -m pip
pk_pipx=${pk_python} -m pipx
pk_app=${pk_pipx_home_path}/venvs/${pk_name}/bin/${pk_name}

# uninstall plapperkasten
PIPX_HOME=${pk_pipx_home_path} ${pk_pipx} uninstall ${pk_name}

# uninstall pipx
${pk_pip} uninstall pipx

# uninstall python
PYENV_ROOT=${pk_pyenv_path} ${pk_pyenv} uninstall ${pk_python_version}

# remove directory
rm -r ${pk_app_path}


# remove service
sudo systemctl stop plapperkasten.service
sudo systemctl disable plapperkasten.service
sudo rm /etc/systemd/system/plapperkasten.service

# remove shutdown routine
sudo rm /lib/systemd/system-shutdown/plapperkasten_poweroff.shutdown

# remove udev rules
sudo rm /etc/udev/rules.d/99-userdev_input.rules
```
