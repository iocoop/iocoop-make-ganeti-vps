#!/bin/bash

/root/bin/make-access-files.py
scp /root/vps/attributes.py betelgeuse-private:/home/vps/bin/attributes.py
scp /root/vps/authorized_keys betelgeuse-private:/home/vps/.ssh/authorized_keys

