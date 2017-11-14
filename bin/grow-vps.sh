#!/bin/bash
#
# Author: Ben Kochie <ben@nerp.net>
#
# Add shares to cernio VPS machines

# Where to get patchs/files from
SRC="/root/make-vps"

# Default sizes for shares in MB
SHARE_RAM_SIZE=1024
SHARE_DISK_SIZE=25600

usage() {
  cat << USAGE
usage $(basename $0) -h -n <hostname> -s <size> [-d <extra_disk_shares>]
  -d    Optional: Extra disk shares of size $((SHARE_DISK_SIZE / 1024))G
  -n    The hostname for the instance (must resolve)
  -s    Number of additional shares (0-8) $((SHARE_RAM_SIZE / 1024))G ram / $((SHARE_DISK_SIZE / 1024))G disk
USAGE
}

declare -i OPTIND=1 help=0 shares=0 extra_disk=0 add_only=0
declare opt="" optarg="" target_name="" ostype="debootstrap+default"
while getopts 'd:hn:s:' opt ; do
  case ${opt} in
    d) extra_disk="${OPTARG}" ;;
    h) help=1 ;;
    n) target_name="${OPTARG}" ;;
    s) shares="${OPTARG}" ;;
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

if [ -z "${target_name}" ] ; then
  usage
  exit 1
fi

instance_info() {
  if [[ $# -ne 2 ]] ; then
    return 1
  fi
  gnt-instance list --no-headers --units=m -o "$1" "$2" 2>/dev/null
}
 
target_test=$(instance_info name "${target_name}" | awk '{print $1}')
if [ -z "${target_test}" ] ; then
  echo "ERROR: '${target_name}' needs to exist"
  usage
  exit 1
fi

target_ip=$(getent ahostsv4 "${target_name}" | awk '{print $1}' | head -n1)

if [ -z "${target_ip}" ] ; then
  echo "ERROR: Invalid hostname '${target_name}'"
  usage
  exit 1
fi

if [ "${shares}" -lt 1 -a "${shares}" -gt 7 ] ; then
  echo "ERROR: Invalid number of shares: ${shares}"
  usage
  exit 1
fi

current_ram=$(instance_info be/maxmem "${target_name}")
additional_ram=$((shares * SHARE_RAM_SIZE))
requested_ram=$((current_ram + additional_ram))

if [ "${requested_ram}" -gt 8192 ] ; then
  echo "ERROR: Requested ram (${requested_ram}) is > 8192M"
  exit 1
fi

if [ "${extra_disk}" -lt 0 -a "${extra_disk}" -gt 7 ] ; then
  echo "ERROR: Invalid number of extra disk shares: ${extra_disk}"
  usage
  exit 1
fi

if [ "${extra_disk}" -gt "${shares}" ] ; then
  echo "ERROR: Extra disk shares must be less than or equal to the primary shares"
  exit 1
fi

current_disk=$(instance_info disk.size/0 "${target_name}")
additional_disk=$((SHARE_DISK_SIZE * (shares + extra_disk)))
requested_disk=$((current_disk + additional_disk))

echo "INFO: Growing vps"
echo "Instance name: ${target_name}"
echo "Shares: ${shares}"
echo "  * Ram - Old:${current_ram}M New:${requested_ram}M"
echo "  * Disk - Old:${current_disk}M New:${requested_disk}M"

# Sync files before we try and do anything.
/root/bin/sync-ganeti-files.sh > /dev/null

# Set the new memory max
echo "INFO: Growing memory"
gnt-instance modify -B memory="${requested_ram}" "${target_name}"

echo "INFO: Growing disk"
gnt-instance grow-disk "${target_name}" 0 "${additional_disk}M"

echo "INFO: All done, Please restart the instance"
