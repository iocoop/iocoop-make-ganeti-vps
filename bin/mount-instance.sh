#!/bin/bash
#
# Author: Ben Kochie <ben@nerp.net>

usage() {
  cat << USAGE
usage $(basename $0) -h -n <hostname>
  -n <hostname>    The hostname for the instance (must resolve)
  -u               Unmount the instance disk
USAGE
}

declare -i OPTIND=1 help=0 unmount=0
declare opt="" optarg="" target_name=""
while getopts 'hn:u' opt ; do
  case ${opt} in
    h) help=1 ;;
    n) target_name="${OPTARG}" ;;
    u) unmount=1 ;;
    *)
      echo "ERROR: unrecognized flag '${opt}'"
      ${script} -h
      exit 1
    ;;
  esac
done
shift $((OPTIND - 1))

if [ "${help}" -eq 1 ] ; then
  usage
  exit
fi

target_ip=$(getent ahostsv4 "${target_name}" | awk '{print $1}' | head -n1)

if [ -z "${target_ip}" ] ; then
  echo "ERROR: Invalid hostname '${target_name}'"
  usage
  exit 1
fi

get_mount() {
  local target_name="$1"
  egrep "^\/dev\/mapper\/${target_name}:" /proc/mounts
}

mount_target() {
  local target_name="$1"

  mount_info="$(get_mount "${target_name}")"
  if [ -n "${mount_info}" ] ; then
    echo "ERROR: ${target_name} already mounted"
    return 1
  fi

  # Make a directory to modify the target
  mkdir -p /mnt/make-vps
  target=$(mktemp -d /mnt/make-vps/target_XXXXXXX)

  # Mount the target disk
  instance_disk="/var/run/ganeti/instance-disks/${target_name}:0"
  if [ ! -h "${instance_disk}" ] ; then
    echo "ERROR: ${instance_disk} not available on this machine"
    return 1
  fi

  target_dev="/dev/mapper/$(kpartx -av "${instance_disk}" | awk '{print $3}')"
  sleep 2
  echo "INFO: Attempting to mount '${target_dev}'"
  mount "${target_dev}" "${target}"

  if [ ! -d "${target}/root" ] ; then
    echo "ERROR: Unable to mount ${instance_disk} in ${target}"
    return 1
  fi

  echo "INFO: Mountpoint: ${target}"
}

unmount_target() {
  echo "Unmounting ${target_name}"
  mount_info="$(get_mount "${target_name}")"
  if [ -z "${mount_info}" ] ; then
    echo "ERROR: ${target_name} not mounted"
    return 1
  fi
  umount "/dev/mapper/${target_name}:0p1"
  if [ $? -eq 0 ] ; then
    echo "INFO: Unmount OK"
    kpartx -dv "/var/run/ganeti/instance-disks/${target_name}:0"
  else
    echo "ERROR: Couldn't unmount ${target_name}"
    return 1
  fi
  echo "INFO: Removed partition mapping"
  mountpoint=$(echo "${mount_info}" | awk '{print $2}')
  rmdir -v "${mountpoint}"
}

if [ ${unmount} -eq 0 ] ; then
  mount_target "${target_name}"
  exit $?
else
  unmount_target "${target_name}"
  exit $?
fi
