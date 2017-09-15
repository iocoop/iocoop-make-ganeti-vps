#!/bin/bash
#
# Author: Ben Kochie <ben@nerp.net>

# The code below is only needed for after first boot install of some packages
# Feel free to remove the contents

if [ -f /root/.tweak-completed ] ; then
  exit 0
fi

logger "Starting first boot package fixes"

export PROXY_IP="204.246.122.1"
export PKG_LIST="ubuntu-standard ssh openssl-blacklist openssl-blacklist-extra"
export DEBIAN_FRONTEND="noninteractive"
export http_proxy="http://${PROXY_IP}:8000"

# Wait for network to be up
timeout=60
down=1
n=0
while [ ${down} -ne 0 ] ; do
  echo "Network test $(date)"
  ping -q -n -c 1 "${PROXY_IP}" > /dev/null
  down=$?
  sleep 1
  n=$((n+1))
  if [ "${n}" -gt "${timeout}" ] ; then
    echo "ERROR: network timeout"
    exit 1
  fi
done

# Setup some basic packages
{
  echo "INFO: Updating package list"
  apt-get update
  echo "INFO: Updating installed packages"
  apt-get -y dist-upgrade
  echo "INFO: Installing extra packages ${PKG_LIST}"
  apt-get -y install ${PKG_LIST}
}

dpkg -l ssh > /dev/null
if [ $? -ne 0 ] ; then
  echo "ERROR: package setup didn't work"
  exit 1
fi

# Disable password authentication for the host
echo "PasswordAuthentication no" >> "/etc/ssh/sshd_config"

# Preseed answers for grub-pc
debconf-set-selections << 'GRUBPC'
grub-pc grub2/linux_cmdline_default string
grub-pc grub2/linux_cmdline string console=tty1 console=ttyS0,38400n8
grub-pc grub-pc/install_devices string /dev/vda
GRUBPC

apt-get -y install grub-pc

# Preseed answers for unattended-upgrades
debconf-set-selections << 'UPGRADES'
unattended-upgrades/enable_auto_updates boolean true
UPGRADES

apt-get -y install unattended-upgrades

# Configure for serial console
cat >> /etc/default/grub << 'GRUBDEFAULT'
GRUB_TERMINAL=serial
GRUB_SERIAL_COMMAND="serial --speed=38400 --unit=0 --word=8 --parity=no --stop=1"
GRUBDEFAULT

# Install a shiny linux image
apt-get -y install linux-image-amd64

# Enable virtio random module
echo "virtio-rng" >> "${target}/etc/modules"

# clean the archive
apt-get clean

# Make sure we don't do this again
cat > /root/.tweak-completed << COMPLETE
This file is a lock for /etc/rc.local
Completed on $(date)
COMPLETE

logger "Finished first boot package fixes"
