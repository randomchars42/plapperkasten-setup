# name of the application
NAME := plapperkasten

# the os of the raspberry pi image
# set either to "debian" for Raspberry Pi Debian Bullseye or
# "ubuntu" for Ubuntu Server 2022
OS := debian

# the sound system to use
# Debian Bullseye and Ubuntu Server use ALSA by default
# PipeWire offers better bluetooth integration and easier switching of audio
# configurations (e.g., switching from an external sound card to the internal
# one) without the whole process needing elevated privileges
# set either to "pipewire" or "alsa"
AUDIO := pipewire

# the music server that runs in the background
# currently controlled by the "mpdclient" plugin so it needs to have an MPD
# interface
# MPD is the older, perhaps more mature choice
# Mopidy is written in python and might give additional functions
# set either to "mpd" or "mopidy"
MUSICSERVER := mpd

# user and group under which the application will run
ifeq ($(OS),ubuntu)
	# ubuntu's default user on the raspberry pi image of Ubuntu Server
	PLK_USER := ubuntu
	PLK_GROUP := ubuntu
else
	# the name can be set in the raspberry pi image of Debian Bullseye
	# see prepare_system.sh and config.conf
	PLK_USER := $(NAME)
	PLK_GROUP := $(NAME)
endif

# path under which the media files reside
DATA_PATH := /data/$(NAME)
# path to install the application in
APP_PATH := $(DATA_PATH)/$(NAME)
# python version to use (must include patch number [major.minor.patch])
PYTHON_VERSION := 3.10.4
# is a Pimoroni OnOffShim present?
ON_OFF_SHIM := 1
# location of the python libgpiod bindings
GPIOD_CPYTHON := /lib/python3/dist-packages/gpiod.cpython-39-aarch64-linux-gnu.so

override MAKEFILE_DIR=$(dir $(firstword $(MAKEFILE_LIST)))
# short python version the dirty way: remove trailing patch number
override PYTHON_VERSION_SHORT := $(basename $(PYTHON_VERSION))
# install pyenv, python and pipx in directories below $(APP_PATH)
override PYENV_PATH := $(APP_PATH)/pyenv
override PIPX_SITE_PACKAGES := $(PYENV_PATH)/versions/$(PYTHON_VERSION)/lib/python$(PYTHON_VERSION_SHORT)/site-packages
override PIPX_MODULE := $(PIPX_SITE_PACKAGES)/pipx/main.py
override PIPX_HOME_PATH := $(APP_PATH)/pipx
export PIPX_HOME_PATH
# executables that will be installed
override PYTHON_VERSION_PATH := $(PYENV_PATH)/versions/$(PYTHON_VERSION)
override PYTHON := PYENV_ROOT=$(PYENV_PATH) $(PYTHON_VERSION_PATH)/bin/python
override PYENV := $(PYENV_PATH)/bin/pyenv
override PIP := $(PYTHON) -m pip
override PIPX := $(PYTHON) -m pipx
override APP := $(PIPX_HOME_PATH)/venvs/$(NAME)/bin/$(NAME)
override APP_CONFIG_PATH := /home/$(PLK_USER)/.config/$(NAME)

#
override USER := $(shell whoami)
ifeq (root, $(USER))
override CALLER := sudo -u $(PLK_USER)
else
ifeq ($(PLK_USER), $(USER))
override CALLER :=
else
$(error "You need to be either root or $(PLK_USER)")
endif
endif

# default target:
#  - create app directory $(APP_PATH) - before
#  - installing pyenv - before
#  - installing python - before
#  - installing pipx - before
#  - making the application available
.PHONY: install_plapperkasten
install_plapperkasten: $(APP) install_config install_events

.PHONY: install_git
install_git: | root
	@if ! command -v git &> /dev/null; then \
		echo "installing git"; \
		sudo apt install git; \
		fi;

# create $(APP_PATH), copy this Makefile into it and install pyenv
$(PYENV): | install_git
	@echo "installing pyenv to $(PYENV_PATH)"
	@$(CALLER) git clone https://github.com/pyenv/pyenv.git $(PYENV_PATH)

# install $(PYTHON) to $(PYTHON_PATH) after installing $(PYENV)
$(PYTHON_VERSION_PATH): $(PYENV)
	@echo "installing python $(PYTHON_VERSION)"
	-@$(CALLER) PYENV_ROOT=$(PYENV_PATH) $(PYENV) install $(PYTHON_VERSION)

# install pipx after installing $(PYTHON) to $(PYTHON_VERSION_PATH)
$(PIPX_MODULE): $(PYTHON_VERSION_PATH)
	@echo "installing pipx"
	@$(CALLER) $(PIP) install pipx

# create the config directory
$(APP_CONFIG_PATH):
	@echo "creating config directory: $(APP_CONFIG_PATH)"
	@$(CALLER) mkdir -p $(APP_CONFIG_PATH)

# create a default configuration
$(APP_CONFIG_PATH)/config.yaml: templates/template_pk_conf
	@echo "creating $(APP_CONFIG_PATH)/config.yaml (creating a backup if necessary)"
	@if test -f $(APP_CONFIG_PATH)/config.yaml; then \
		$(CALLER) cp --backup=numbered $(APP_CONFIG_PATH)/config.yaml $(APP_CONFIG_PATH)/config.yaml.bk; \
		fi;
	@$(CALLER) envsubst '$${PLK_USER} $${APP_PATH}' < templates/template_pk_conf > $(APP_CONFIG_PATH)/config.yaml

# create a default events.map
$(APP_CONFIG_PATH)/events.map: templates/template_eventsmap
	@echo "creating $(APP_CONFIG_PATH)/events.map if it does not already exist"
	@$(CALLER) cp -n templates/template_eventsmap $(APP_CONFIG_PATH)/events.map

# make application available application after installing $(PIPX_MODULE) and
# config files
#  "--system-site-packages" is needed to include libs only installable via
#  python3-gpiod on Ubuntu / Debian
$(APP): $(PIPX_MODULE) | $(APP_CONFIG_PATH) $(APP_CONFIG_PATH)/config.yaml $(APP_CONFIG_PATH)/events.map
	@echo "installing $(NAME)"
	@$(CALLER) PIPX_HOME=$(PIPX_HOME_PATH) $(PIPX) install --system-site-packages $(NAME)

.PHONY: install_config
install_config: $(APP_CONFIG_PATH)/config.yaml

.PHONY: install_events
install_events: $(APP_CONFIG_PATH)/events.map

.PHONY: run
run:
	@$(CALLER) $(NAME)

.PHONY: upgrade
upgrade:
	@echo "upgrading $(NAME)"
	@$(CALLER) PIPX_HOME=$(PIPX_HOME_PATH) $(PIPX) upgrade $(NAME)

# reverse installation of plapperkasten
.PHONY: clean
clean:
	@echo "uninstalling $(NAME)"
	-@$(CALLER) PIPX_HOME=$(PIPX_HOME_PATH) $(PIPX) uninstall $(NAME)
	@echo "uninstalling pipx"
	@$(CALLER) $(PIP) uninstall pipx
	@echo "uninstalling python"
	-@$(CALLER) PYENV_ROOT=$(PYENV_PATH) $(PYENV) uninstall $(PYTHON_VERSION)
	@echo "removing configuration"
	@$(CALLER) rm -r $(APP_CONFIG_PATH)

# does nothing except checking if the Makefile has been invoked with elevated
# privileges
.PHONY: root
root:
ifneq ($(shell whoami), root)
	@$(error "You need to be root")
endif

# integrate plapperkasten into the system by
# - creating and enabling the user system service
# - creating a shutdown routine
# - creating a udev rule for access to gpio events
# - making libgpiod available
# - configuring audio (default: PipeWire, see $AUDIO)
# - configuring the music server (default: MPD, see $MUSICSERVER)
.PHONY: setup_system
setup_system: install_plapperkasten \
	setup_service \
	install_gpiodmonitor \
	setup_poweroff \
	setup_sudoers \
	setup_mpd \
	setup_audio \
	setup_musicserver \
	| root

# create user service
# only makes sense if lingering is enabled (setup_logind)
.PHONY: setup_service
setup_service: $(APP_PATH)/$(NAME).service | setup_logind
$(APP_PATH)/$(NAME).service: templates/template_service
	@echo "enabling $(NAME) as a service"
	@$(CALLER) NAME=$(NAME) APP=$(APP) USER=$(PLK_USER) GROUP=$(PLK_GROUP) envsubst < templates/template_service > $(APP_PATH)/$(NAME).service
	@$(CALLER) systemctl --user enable $(APP_PATH)/$(NAME).service

# create udev rules to access gpio events without elevated privileges
.PHONY: setup_udev
setup_udev: /etc/udev/rules.d/99-userdev_input.rules
/etc/udev/rules.d/99-userdev_input.rules: templates/template_udev | root
	@echo "configuring udev"
	@sudo GROUP=$(PLK_GROUP) envsubst < templates/template_udev > /etc/udev/rules.d/99-userdev_input.rules

# install libgpiod needed by gpiodmonitor
.PHONY: install_libgpiod
install_libgpiod: $(GPIOD_CPYTHON)
$(GPIOD_CPYTHON): | root
	@if ! command -v gpioset &> /dev/null; then echo "installing libgpiod" && sudo apt install python3-libgpiod; fi;

# fix on Debian Bullseye
# Bullseyye comes with python 3.9 so when libgiod is compiled the object is for
# cpython3.9 but we can copy it to 3.10
# TODO ship with source of libgpiod
.PHONY: setup_libgpiod
setup_libgpiod: $(PIPX_SITE_PACKAGES)/gpiod.cpython-310-aarch64-linux-gnu.so | install_libgpiod
$(PIPX_SITE_PACKAGES)/gpiod.cpython-310-aarch64-linux-gnu.so: install_libgpiod $(GPIOD_CPYTHON)
	@echo "making gpiod files accessible"
	@$(CALLER) cp $(GPIOD_CPYTHON) $(PIPX_SITE_PACKAGES)/gpiod.cpython-310-aarch64-linux-gnu.so

# gpiodmonitor is used in the "inputgpiod" plugin
# it in turn depends on libgpiod
# and can only be accessed without elevated privileges if the correct udev rules
# # are in place
.PHONY: install_gpiodmonitor
install_gpiodmonitor: | setup_libgpiod setup_udev
	@if ! test -f $(PIPX_SITE_PACKAGES)/gpiodmonitor/gpiodmonitor.py; then \
		echo "installing gpiodmonitor"; \
		$(CALLER) PIPX_HOME=$(PIPX_HOME_PATH) $(PIPX) inject $(NAME) gpiodmonitor; \
		fi;

# create poweroff script
# only useful with a Pimoroni OnOffShim
# this uses gpioset to pull gpio pin 4 and thus pull the power
.PHONY: setup_poweroff
setup_poweroff: /lib/systemd/system-shutdown/$(NAME)_poweroff.shutdown
/lib/systemd/system-shutdown/$(NAME)_poweroff.shutdown: templates/template_poweroff | root install_libgpiod
ifeq ($(ON_OFF_SHIM), 1)
	@echo "creating poweroff script"
	@sudo cp templates/template_poweroff /lib/systemd/system-shutdown/$(NAME)_poweroff.shutdown
	@sudo chmod +x /lib/systemd/system-shutdown/$(NAME)_poweroff.shutdown
endif

# allow lingering (i.e. start user services without a user logging in and do not
# stop them after the user has logged out
# see `man 5 logind.conf`
.PHONY: setup_logind
setup_logind: /etc/systemd/logind.conf.d/$(NAME).conf
/etc/systemd/logind.conf.d/$(NAME).conf: templates/template_logind_conf | root
	@echo "configuring logind"
	@sudo mkdir -p /etc/systemd/logind.conf.d
	@sudo USER=$(PLK_USER) envsubst < templates/template_logind_conf > /etc/systemd/logind.conf.d/$(NAME).conf

# create a rule for plapperkasten to use "sudo shutdown" without being asked for
# a password
.PHONY: setup_sudoers
setup_sudoers: /etc/sudoers.d/010_$(NAME)
/etc/sudoers.d/010_$(NAME): templates/template_sudoers | root
	@echo "creating sudoers rule for $(PLK_USER) to use sudo shutdown"
	@sudo USER=$(PLK_USER) envsubst < templates/template_sudoers > /etc/sudoers.d/010_$(NAME)

# implicit rule to create directories under $(DATA_PATH)
$(DATA_PATH)/%:
	@echo "preparing app directory $@"
	@sudo mkdir -p $@
	@sudo chown -R $(PLK_USER):$(PLK_GROUP) $(DATA_PATH)

# install mpd
# use "testing" for a newer (stil supported) version
.PHONY: install_mpd
install_mpd: | root
	@if ! command -v mpd &> /dev/null; then \
		echo "installing mpd"; \
		sudo apt -t testing install mpd; \
		sudo systemctl enable mpd; \
		sudo systemctl start mpd; \
		fi;

# create mpd.conf
.PHONY: setup_mpd
configure_mpd: /etc/mpd.conf
/etc/mpd.conf: templates/template_mpd \
	| root \
	install_mpd \
	$(DATA_PATH)/MPD \
	$(DATA_PATH)/mpd/playlists \
	$(DATA_PATH)/Media/Playlists \
	$(DATA_PATH)/Media/Music \
	$(DATA_PATH)/Media/Audiobooks
	@echo "setting up mpd"
	@if test -f /etc/mpd.conf; then sudo mv -n /etc/mpd.conf /etc/mpd.conf.bk; fi;
	@sudo USER=$(PLK_USER) DATA_PATH="$(DATA_PATH)" envsubst < templates/template_mpd > /etc/mpd.conf
	@sudo systemctl restart mpd

# install mopidy
.PHONY: install_mopidy
install_mopidy:
	@if ! command -v mopidy &> /dev/null; then \
		echo "installing mopidy" \
		sudo mkdir -p /usr/local/share/keyrings; \
		sudo wget -q -O /usr/local/share/keyrings/mopidy-archive-keyring.gpg https://apt.mopidy.com/mopidy.gpg; \
		sudo wget -q -O /etc/apt/sources.list.d/mopidy.list https://apt.mopidy.com/buster.list; \
		sudo apt update; \
		sudo apt install mopidy mopidy-mpd mopidy-local; \
		$(CALLER) systemctl --user enable mopidy.service; \
		$(CALLER) systemctl --user start mopidy.service; \
		fi;

# create mopidy.conf
.PHONY: setup_mopidy
configure_mopidy: /etc/mopidy/mopidy.conf
/etc/mopidy.conf: templates/template_mopidy \
	| root \
	install_mopidy \
	$(DATA_PATH)/Mopidy/config \
	$(DATA_PATH)/Mopidy/cache \
	$(DATA_PATH)/Mopidy/data \
	$(DATA_PATH)/Media/Playlists \
	$(DATA_PATH)/Media/Music \
	$(DATA_PATH)/Media/Audiobooks
	@echo "setting up mopidy"
	@if test -f /etc/mopidy/mopidy.conf; then sudo mv -n /etc/mopidy/mopidy.conf /etc/mopidy/mopidy.conf.bk; fi;
	@sudo USER=$(PLK_USER) DATA_PATH="$(DATA_PATH)" envsubst < templates/template_mopidy > /etc/mopidy/mopidy.conf
	@sudo chmod 644 /etc/mopidy/mopidy.conf
	@$(CALLER) systemctl --user restart mopidy

# create a file with bash_aliases to quickly controll plapperkasten and its
# associated programmes
.PHONY: setup_bash_aliases
setup_bash_aliases: $(APP_PATH)/.bash_aliases
$(APP_PATH)/.bash_aliases: templates/template_bash_aliases
	@$(CALLER) NAME=$(NAME) APP_PATH=$(APP_PATH) PIPX_HOME_PATH=$(PIPX_HOME_PATH) PIPX=$(PIPX) DATA_PATH=$(DATA_PATH) USER=$(PLK_USER) envsubst < templates/template_bash_aliases > $(APP_PATH)/bash_aliases
	@echo copy \"source $(APP_PATH)/bash_aliases into /home/$(PLK_USER)/.bashrc\"

# install wireplumber and pipewire
#
# installation instructions:
# https://wiki.debian.org/PipeWire
#
# using port 4713 as a workaround for MPD / Mopidy running as system service:
# https://github.com/mopidy/mopidy/issues/1974#issuecomment-797105715
#
# fix volume control
# https://wiki.archlinux.org/title/WirePlumber
#
# fix RTKit
# https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Performance-tuning#rlimits
.PHONY: install_pipewire_wireplumber
install_pipewire_wireplumber: | root setup_logind
	@if ! command -v wpctl &> /dev/null; then \
		echo 'APT::Default-Release "stable";' | sudo tee /etc/apt/apt.conf.d/99defaultrelease; \
		echo "deb http://ftp.de.debian.org/debian/ testing main contrib non-free" | sudo tee /etc/apt/sources.list.d/testing.list; \
		sudo apt update; \
		sudo apt -t testing install pipewire wireplumber libspa-0.2-bluetooth pipewire-audio-client-libraries; \
		cp -n /usr/share/doc/pipewire/examples/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d/; \
		sudo sed -i 's/#"tcp:4713"/"tcp:4713" /' /usr/share/pipewire/pipewire-pulse.conf; \
		cat templates/template_wireplumber_alsa-custom_lua | sudo tee -a /usr/share/wireplumber/main.lua.d/50-alsa-config.lua; \
		sudo cp templates/template_pipewire_limits /etc/security/limits.d/95-pipewire.conf; \
		sudo sed -i 's%ExecStart=/usr/libexec/rtkit-daemon%ExecStart=/usr/libexec/rtkit-daemon --scheduling-policy=FIFO --our-realtime-priority=89 --max-realtime-priority=88 --min-nice-level=-19 --rttime-usec-max=2000000 --users-max=100 --processes-per-user-max=1000 --threads-per-user-max=10000 --actions-burst-sec=10 --actions-per-burst-max=1000 --canary-cheep-msec=30000 --canary-watchdog-msec=60000%' /lib/systemd/system/rtkit-daemon.service; \
		sudo usermod -a -G pipewire $(PLK_USER); \
		fi;

# implicit rule to copy template files beginning with "template_asound_" to the
# app directory so that the "soundalsa" plugin can link them
$(APP_PATH)/asound_%.conf: templates/template_asound_%
	@echo "preparing asound configuration $@"
	@$(CALLER) cp -b $< $@

# install example configuration files which might be linked by "soundalsa"
# at the moment there is no way for plapperkasten to get mpd or mopidy to use
# those new profiles without restarting the service
# thus, the default is to use pipewire / wireplumber
.PHONY: install_asound_config
install_asound_config: $(APP_PATH)/asound_headphones.conf $(APP_PATH)/asound_speaker.conf

.PHONY: setup_audio
setup_audio:
	@echo "audio system: $(AUDIO)"
ifeq ($(AUDIO), alsa)
	$(MAKE) install_asound_config
else
	$(MAKE) install_pipewire_wireplumber
endif

.PHONY: setup_musicserver
setup_musicserver:
	@echo "music server: $(MUSICSERVER)"
ifeq ($(MUSICSERVER), mopidy)
	@$(MAKE) configure_mopidy
else
	@$(MAKE) configure_mpd
endif

# uninstall system integration after removing the application
.PHONY: clean_system
clean_system: clean | root
	@echo "removing $(NAME) service"
	-@$(CALLER) systemctl --user stop $(NAME).service
	-@$(CALLER) systemctl --user disable $(NAME).service
	@echo "removing poweroff script"
	-@sudo rm /lib/systemd/system-shutdown/$(NAME)_poweroff.shutdown
	@echo "removing udev rule"
	-@sudo rm /etc/udev/rules.d/99-userdev_input.rules
ifeq ($(AUDIO), alsa)
	@echo "removing ALSA configuration"
	-@sudo rm /home/$(PLK_USER)/.asoundrc
	@if test -f /home/$(PLK_USER)/.asoundrc.bk; then sudo mv /home/$(PLK_USER)/.asoundrc.bk /home/$(PLK_USER)/.asoundrc; fi;
	-@sudo alsactl restore
endif
ifeq ($(MUSICSERVER), mpd)
	@echo "restoring MPD configuration"
	-@sudo rm /etc/mpd.conf
	-@if test -f /etc/mpd.conf.bk; then sudo mv /etc/mpd.conf.bk /etc/mpd.conf; fi;
	-@sudo systemctl restart mpd
endif
	@echo "removing files"
	-@sudo rm -r $(APP_PATH)
	@echo "removing config_files"
	-@$(CALLER) rm -r /home/$(PLK_USER)/.config/$(NAME)
	@echo "trying to remove sudoers configuration"
	-@sudo rm /etc/sudoers.d/010_$(NAME)
	@echo "trying to remove logind configuration"
	-@rm /etc/systemd/logind.conf.d/$(NAME).conf

# play a test sound depending on the audio system (see $(AUDIO))
.PHONY: test_sound
test_sound:
ifeq ($(AUDIO), alsa)
	@-alsactl restore
	@speaker-test -c2 --test=wav -w /usr/share/sounds/alsa/Front_Center.wav
else
	@pw-play --target=63 /usr/share/sounds/alsa/Front_Center.wav
endif
