#!/bin/bash

source /root/make-vps/bin/vps-lib.sh

/root/bin/make-access-files.py

if [[ $? -ne 0 ]] ; then
  echo 'ERROR: Failed to generate access files'
  exit 1
fi

# Add root's DSA key to the authorized_keys.
cat /root/.ssh/id_dsa.pub >> /root/vps/authorized_keys

manager="$(json_read /etc/make-vps.json manager)"
scp /root/vps/attributes.py ${manager}:/home/vps/bin/attributes.py
scp /root/vps/authorized_keys ${manager}:/home/vps/.ssh/authorized_keys
