# name of the application
export NAME := plapperkasten
# user and group under which the application will run
export INSTALL_USER := ubuntu
export INSTALL_GROUP := ubuntu
# path to install the application in
APP_PATH := ~/$(NAME)
# python version to use (must include patch number [major.minor.patch])
PYTHON_VERSION := 3.10.4
# path under which the media files reside (look at template_mpd)
export DATA_PATH := /data/plapperkasten

override MAKEFILE_DIR=$(dir $(firstword $(MAKEFILE_LIST)))
# short python version the dirty way: remove trailing patch number
override PYTHON_VERSION_SHORT := $(basename $(PYTHON_VERSION))
# install pyenv, python and pipx in directories below $(APP_PATH)
override PYENV_PATH := $(APP_PATH)/pyenv
override PIPX_MODULE := $(PYENV_PATH)/versions/$(PYTHON_VERSION)/lib/python$(PYTHON_VERSION_SHORT)/site-packages/pipx/main.py
override PIPX_HOME_PATH := $(APP_PATH)/pipx
# executables that will be installed
override PYTHON_VERSION_PATH := $(PYENV_PATH)/versions/$(PYTHON_VERSION)
override PYTHON := PYENV_ROOT=$(PYENV_PATH) $(PYTHON_VERSION_PATH)/bin/python
override PYENV := $(PYENV_PATH)/bin/pyenv
override PIP := $(PYTHON) -m pip
override PIPX := $(PYTHON) -m pipx
override APP := $(PIPX_HOME_PATH)/venvs/$(NAME)/bin/$(NAME)

# files with those names should not trigger any recipe
.PHONY = setup install clean uninstall run upgrade

# default target:
#  - create app directory $(APP_PATH) - before
#  - installing pyenv - before
#  - installing python - before
#  - installing pipx - before
#  - making the application available
setup: $(APP)

# create $(APP_PATH), copy this Makefile into it and install pyenv
$(PYENV):
	mkdir -p $(APP_PATH)
	cp $(MAKEFILE_DIR)/Makefile $(APP_PATH)/
	@echo installing pyenv to $(PYENV_PATH)
	git clone https://github.com/pyenv/pyenv.git $(PYENV_PATH)

# install $(PYTHON) to $(PYTHON_PATH) after installing $(PYENV)
$(PYTHON_VERSION_PATH): $(PYENV)
	@echo installing python $(PYTHON_VERSION)
	- PYENV_ROOT=$(PYENV_PATH) $(PYENV) install $(PYTHON_VERSION)

# install pipx after installing $(PYTHON) to $(PYTHON_VERSION_PATH)
$(PIPX_MODULE): $(PYTHON_VERSION_PATH)
	@echo installing pipx
	$(PIP) install pipx

# make application available application after installing $(PIPX_MODULE)
$(APP): $(PIPX_MODULE)
	@echo installing $(NAME)
	#  --system-site-packages is needed to include libs only installable via
	#  python3-gpiod on ubuntu
	PIPX_HOME=$(PIPX_HOME_PATH) $(PIPX) --system-site-packages install $(NAME)

run:
	$(NAME)

upgrade:
	PIPX_HOME=$(PIPX_HOME_PATH) $(PIPX) upgrade $(NAME)

clean:
	@echo uninstalling $(NAME)
	- PIPX_HOME=$(PIPX_HOME_PATH) $(PIPX) uninstall $(NAME)
	@echo uninstalling pipx
	$(PIP) uninstall pipx
	@echo uninstalling python
	- PYENV_ROOT=$(PYENV_PATH) $(PYENV) uninstall $(PYTHON_VERSION)

# integrate application into the system by
# - making application available - before
# - creating and enabling the system service - and
# - creating a shutdown routine - and
# - creating a udev rule
# - configuring ALSA
# - configuring MPD
install: setup /etc/systemd/system/$(NAME).service /lib/systemd/system-shutdown/$(NAME)_poweroff.shutdown /etc/udev/rules.d/99-userdev_input.rules /etc/asound.conf /etc/mpd.conf

# create service if template_service has changed
/etc/systemd/system/$(NAME).service: template_service
	envsubst '$${NAME} $${INSTALL_USER} $${INSTALL_GROUP}' < template_service > $(NAME).service
	sudo mv $(NAME).service /etc/systemd/system/
	sudo systemctl enable $(NAME).service

# create shutdown routine if template_poweroff has changed
/lib/systemd/system-shutdown/$(NAME)_poweroff.shutdown: template_poweroff
ifeq (, $(shell which gpioset))
	@echo no gpioset in $(PATH), consider installing python3-libgpiod
else
	sudo cp template_poweroff /lib/systemd/system-shutdown/$(NAME)_poweroff.shutdown
	sudo chmod +x /lib/systemd/system-shutdown/$(NAME)_poweroff.shutdown
endif

# create udev rules if template_udev has changed
/etc/udev/rules.d/99-userdev_input.rules: template_udev
ifeq (, $(shell which gpioset))
	@echo no gpioset in $(PATH), consider installing python3-libgpiod
else
	envsubst '$${INSTALL_GROUP}' < template_udev > 99-userdev_input.rules
	sudo mv ./99-userdev_input.rules /etc/udev/rules.d/
endif

# create asound.conf if template_asound has changed
/etc/asound.conf: template_asound
	sudo mv -n /etc/asound.conf /etc/asound.conf.bk
	sudo cp template_asound /etc/asound.conf
	sudo alsactl restore

# create mpd.conf if template_mpd has changed
/etc/mpd.conf: template_mpd
	sudo mv -n /etc/mpd.conf /etc/mpd.conf.bk
	envsubst '$${INSTALL_USER} $${DATA_PATH}' < template_mpd > mpd.conf
	sudo cp mpd.conf /etc/mpd.conf
	sudo systemctl restart mpd

# uninstall system integration after removing the application
uninstall: clean
	@echo removing service
	- sudo systemctl stop $(NAME).service
	sudo systemctl disable $(NAME).service
	sudo rm /etc/systemd/system/$(NAME).service
	@echo removing poweroff
	- sudo rm /lib/systemd/system-shutdown/$(NAME)_poweroff.shutdown
	@echo removing udev
	- sudo rm /etc/udev/rules.d/99-userdev_input.rules
	@echo restoring ALSA configuration
	sudo rm /etc/asound.conf
	sudo mv /etc/asound.conf.bk /etc/asound.conf
	sudo alsactl restore
	@echo restoring MPD configuration
	sudo rm /etc/mpd.conf
	sudo mv /etc/mpd.conf.bk /etc/mpd.conf
	sudo systemctl restart mpd
	@echo removing files
	sudo rm -r $(APP_PATH)
