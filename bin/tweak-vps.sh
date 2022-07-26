#!/bin/bash
#
# Author: Ben Kochie <ben@nerp.net>
#
# Tweak VPS after creation

source /root/make-vps/bin/vps-lib.sh
if ! check_for_bins; then
  exit 1
fi

usage() {
  cat << USAGE
usage $(basename $0) -h -n <hostname>
  -n    The hostname for the instance (must resolve)
USAGE
}

declare -i OPTIND=1 help=0
declare opt="" optarg="" target_name=""
while getopts 'hn:' opt ; do
  case ${opt} in
    h) help=1 ;;
    n) target_name="${OPTARG}" ;;
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

eval $(vlan_info "${target_ip}")

target_keyfile="${SRC}/keys/${target_name}"
if [ ! -f "${target_keyfile}" ] ; then
  echo "ERROR: Invalid target ssh keyfile ${target_keyfile}"
  exit 1
fi

echo "INFO: Getting instance info from API"
instance_info=$(get_instance_info "${target_name}")

ostype=$(json_read "${instance_info}" "os")

if [ -z "${ostype}" ] ; then
  echo "ERROR: Invalid ostype"
  usage
  exit 1
fi

node1=$(json_read "${instance_info}" "pnode")
me=$(hostname -f)

if [ "${node1}" != "${me}" ] ; then
  echo "ERROR: Script must be run from the primary node ${node1}"
  exit 1
fi

echo "INFO: Tweaking vps"
echo "Instance name: ${target_name}"
echo "Target IP: ${target_ip}"
echo "Target OS: ${ostype}"
echo "Primary Node: ${node1}"

# Make a directory to modify the target
mkdir -p /mnt/make-vps
target=$(mktemp -d /mnt/make-vps/target_XXXXXXX)

# Mount the target disk
instance_disk="/var/run/ganeti/instance-disks/${target_name}:0"
if [ ! -h "${instance_disk}" ] ; then
  echo "ERROR: ${instance_disk} not available on this machine"
  exit 1
fi

target_dev="/dev/mapper/$(kpartx -av "${instance_disk}" | awk '{print $3}')"
sleep 2
echo "INFO: Attempting to mount '${target_dev}'"
mount "${target_dev}" "${target}"

if [ ! -d "${target}/root" ] ; then
  echo "ERROR: Unable to mount ${instance_disk} in ${target}"
  exit 1
fi

all_source="${SRC}/all"
ostype_source="${SRC}/${ostype}"

echo "INFO: tweaking files"

# Fix the resolvconf config
if [ -f "${target}/etc/resolvconf/resolv.conf.d/tail" ] ; then
  rm -v "${target}/etc/resolvconf/resolv.conf.d/tail"
fi

# Copy in a nice README file
cp -v "${all_source}/README.txt" "${target}/root/README.txt"

# Copy in the tweak script
cp -v "${all_source}/tweak.sh" "${target}/root/tweak.sh"

# Copy in an rc.local file to update things
cp -v "${ostype_source}/rc.local" "${target}/etc/rc.local"

# Copy in a valid sources.list file
if [ -f "${ostype_source}/sources.list" ] ; then
  cp -v "${ostype_source}/sources.list" "${target}/etc/apt/sources.list"
fi

# Create the root authorized_keys file
mkdir -v -m "0700" "${target}/root/.ssh"
cp -v "${SRC}/keys/${target_name}" "${target}/root/.ssh/authorized_keys"

# Disable password authentication for the host
#echo "PasswordAuthentication no" >> "${target}/etc/ssh/sshd_config"

# Setup the IP address based on an interfaces template.
if [ -f "${ostype_source}/interfaces.TEMPLATE" ] ; then
  sed "s/TARGET_ADDRESS/${target_ip}/ ; s/TARGET_NETMASK/${target_netmask}/ ; s/TARGET_GATEWAY/${target_gateway}/" \
    "${ostype_source}/interfaces.TEMPLATE" \
    > "${target}/etc/network/interfaces"
fi

# Setup the IP address based on a netplan template.
if [ -f "${ostype_source}/netplan.TEMPLATE" ] ; then
  sed "s/TARGET_ADDRESS/${target_ip}/ ; s/TARGET_NETMASK_NUMBER/${target_netmask_number}/ ; s/TARGET_GATEWAY/${target_gateway}/" \
    "${ostype_source}/netplan.TEMPLATE" \
    > "${target}/etc/netplan/eth0.yaml"
fi

# Fix the /etc/hosts file
sed "s/TARGET_NAME/${target_name}/" "${all_source}/hosts.TEMPLATE" \
  > "${target}/etc/hosts"

# Fix /etc/resolf.conf
echo "nameserver 8.8.8.8" > "${target}/etc/resolv.conf"

# Clear the ssh host keys, they may come from a cached install and be unsafe.
#rm -v ${target}/etc/ssh/ssh_host_*_{key,key.pub}

# Cleanup
umount "${target}"
kpartx -dv "${instance_disk}"
rm -v "${instance_info}"
rmdir -v "${target}"
