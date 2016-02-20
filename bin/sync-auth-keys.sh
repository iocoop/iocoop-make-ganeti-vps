#!/bin/bash

source /root/make-vps/bin/vps-lib.sh

/root/bin/make-access-files.py

manager="`json_read /etc/make-vps.json manager`"
scp /root/vps/attributes.py ${manager}:/home/vps/bin/attributes.py
scp /root/vps/authorized_keys ${manager}:/home/vps/.ssh/authorized_keys
