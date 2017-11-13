#!/bin/bash

monitor="/var/run/ganeti/kvm-hypervisor/ctrl/$1.monitor"

if [[ $# != 1 && ! -f "${monitor}" ]] ; then
  echo "usage: $(basename $0) <instance>"
  exit 1
fi

echo "info migrate" | /usr/bin/socat STDIO "UNIX-CONNECT:${monitor}"
