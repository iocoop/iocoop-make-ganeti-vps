#!/bin/bash
#
# Author: Ben Kochie <ben@nerp.net>
#
# Sync a bunch of stuff to the ganeti nodes.

node_list="$(get_nodes | xargs)"
me=$(hostname -s)

dir_list="/etc/ganeti/ /root/make-vps/ /root/debs/ /home/vmconsole/.ssh/ /var/cache/ganeti-instance-image/"
file_list="/etc/hosts /etc/sudoers /etc/default/ganeti-instance-debootstrap /etc/default/ganeti-instance-image"

for node in ${node_list} ; do
  if [ "${node}" != "${me}" ] ; then
    for dir in ${dir_list} ; do
      echo "${node}: syncing ${dir}"
      rsync -a --delete "${dir}" "root@${node}:${dir}"
    done
    for file in ${file_list} ; do
      echo "${node}: syncing ${file}"
      scp -q "${file}" "root@${node}:${file}"
    done
  else
    echo "${node}: Not copying files to myself"
  fi
done

# generate and copy the updated key database
#/root/bin/make-access-files.py
#scp /root/vps/attributes.py betelgeuse-private:/home/vps/bin/attributes.py
#scp /root/vps/authorized_keys betelgeuse-private:/home/vps/.ssh/authorized_keys

