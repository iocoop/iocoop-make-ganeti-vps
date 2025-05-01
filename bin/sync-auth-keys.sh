#!/usr/bin/env bash

source /root/make-vps/bin/vps-lib.sh
if ! check_for_bins; then
  exit 1
fi

if ! mkdir -p /root/vps ; then
  echo 'ERROR: Failed to mkdir /root/vps'
  exit 1
fi

if ! /root/make-vps/bin/make-access-files.py ; then
  echo 'ERROR: Failed to generate access files'
  exit 1
fi

manager="$(json_read /etc/make-vps.json manager)"
scp /root/vps/attributes.py "${manager}:/home/vps/bin/attributes.py"
scp /root/vps/authorized_keys "${manager}:/home/vps/.ssh/authorized_keys"
