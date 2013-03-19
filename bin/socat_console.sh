#!/bin/bash
#
# Author: Ben Kochie <ben@nerp.net>


CTRL_PATH="/var/run/ganeti/kvm-hypervisor/ctrl"

usage() {
  echo "usage: $(basename $0) <vmname>"
}

if [ -n "${SSH_ORIGINAL_COMMAND}" ] ; then
  instance_name="${SSH_ORIGINAL_COMMAND}"
else
  instance_name="$1"
fi

if [ -z "${instance_name}" ] ; then
  usage
  exit 1
fi

if [ ! -S "${CTRL_PATH}/${instance_name}.serial" ] ; then
  echo "ERROR: Invalid instance ${instance_name}"
  usage
  exit 1
fi

echo "Console for: '${instance_name}'"
echo "  Use ^] to disconnect"
echo "  (You might need to press enter to wake up the getty on your instance)"
echo "-----------------------------------------------------------------------------"

/usr/bin/socat \
    "STDIO,raw,echo=0,escape=0x1d" \
    "UNIX-CONNECT:${CTRL_PATH}/${instance_name}.serial"
