#!/bin/bash
#
# Author: Ben Kochie <ben@nerp.net>
#
# Create cernio VPS machines

source "$(dirname $0)/vps-lib.sh"
if ! check_for_bins; then
  exit 1
fi

# Default sizes for shares
SHARE_RAM_SIZE=1
SHARE_DISK_SIZE=25

MAX_CPU_COUNT=8

# Get a list of available OS images from ganeti
os_list=$(gnt-os list | tail -n+2 | xargs)

# Get a list of available nodes
node_list="$(get_nodes | xargs)"

if [[ -z "${os_list}" ]] ; then
  exit 1
fi

usage() {
  cat << USAGE
usage $(basename $0) -h [-a] -n <hostname> -s <size> -o <ostype> [-d <extra_disk_shares>]
  -a    Add only, don't startup and tweak
  -d    Optional: Extra disk shares of size ${SHARE_DISK_SIZE}G
  -n    The hostname for the instance (must resolve)
  -o    OS Type (${os_list})
  -p    Primary Node (${node_list})
  -s    Number of shares (1-8) ${SHARE_RAM_SIZE}G ram / ${SHARE_DISK_SIZE}G disk
USAGE
}

declare -i OPTIND=1 help=0 shares=1 extra_disk=0 add_only=0
declare opt="" optarg="" target_name="" ostype="debootstrap+focal" node1=""
while getopts 'ad:hn:o:p:s:' opt ; do
  case ${opt} in
    a) add_only=1 ;;
    d) extra_disk="${OPTARG}" ;;
    h) help=1 ;;
    n) target_name="${OPTARG}" ;;
    o) ostype="${OPTARG}" ;;
    p) node1="${OPTARG}" ;;
    s) shares="${OPTARG}" ;;
    *)
      echo "ERROR: unrecognized flag '${opt}'"
      ${script} -h
      exit 1
    ;;
  esac
done
shift $((OPTIND - 1))

if [[ "${help}" -eq 1 ]] ; then
  usage
  exit
fi

if [[ -z "${target_name}" ]] ; then
  usage
  exit 1
fi
 
target_test=$(gnt-instance list "${target_name}" 2> /dev/null | tail -n+2 | awk '{print $1}')
if [[ -n "${target_test}" ]] ; then
  echo "ERROR: '${target_name}' already exists"
  usage
  exit 1
fi

target_ip=$(getent ahostsv4 "${target_name}" | awk '{print $1}' | head -n1)

if [[ -z "${target_ip}" ]] ; then
  echo "ERROR: Invalid hostname '${target_name}'"
  usage
  exit 1
fi

eval $(vlan_info "${target_ip}")

if [[ $? -ne 0 ]] ; then
  echo "ERROR: Unable to get vlan for ${target_ip}"
  exit 1
fi

target_keyfile="${SRC}/keys/${target_name}"
if [[ ! -f "${target_keyfile}" ]] ; then
  echo "ERROR: Invalid target ssh keyfile ${target_keyfile}"
  exit 1
fi

test_ssh_keyfile "${target_keyfile}" || exit 1

if [[ "${shares}" -lt 1 && "${shares}" -gt 8 ]] ; then
  echo "ERROR: Invalid number of shares: ${shares}"
  usage
  exit 1
fi

if [[ "${extra_disk}" -lt 0 && "${extra_disk}" -gt 8 ]] ; then
  echo "ERROR: Invalid number of extra disk shares: ${extra_disk}"
  usage
  exit 1
fi

if [[ "${extra_disk}" -gt "${shares}" ]] ; then
  echo "ERROR: Extra disk shares must be less than or equal to the primary shares"
  exit 1
fi

ostype=$(echo ${os_list} | fmt -1 | awk -v "os=${ostype}" '$1 == os')

if [[ -z "${ostype}" ]] ; then
  echo "ERROR: Invalid ostype"
  usage
  exit 1
fi

# The value compared here is "True" not "true" because this is a Python variable not JSON
if [[ "$(json_read /etc/make-vps.json balance_on_free_space)" = "True" ]] ; then
  if [[ -z "${node1}" ]] ; then
    node1=$(get_nodes_disk | sort -rn -k2 | head -n1 | awk '{print $1}')
  fi
  node2=$(get_nodes_disk | sort -rn -k2 | grep -v "${node1}" | head -n1 | awk '{print $1}')
  gnt_node_assertion="-n \"${node1}:${node2}\""
fi

ganeti_disk_type="$(json_read /etc/make-vps.json ganeti_disk_type)"
if [[ -z "${ganeti_disk_type}" ]] ; then
  echo "ERROR: No ganeti_disk_type found in /etc/make-vps.json"
  exit 1
fi

ram_total=$((shares * SHARE_RAM_SIZE))
disk_total=$(((extra_disk + shares) * SHARE_DISK_SIZE))

cat << NODEINFO
INFO: Creating vps
Instance name: ${target_name}
Shares: ${shares}
  * Ram ${ram_total}G
  * Disk ${disk_total}G
Target IP: ${target_ip}
Target vlan: ${target_vlan}
Target netmask: ${target_netmask} (/${target_netmask_number})
Target gateway: ${target_gateway}
Target OS: ${ostype}
NODEINFO

if [ -n "${node1}" ]; then
  echo "Primary Node: ${node1}"
  echo "Secondary Node: ${node2}"
fi

if [[ -z "${node1}" ]]; then
  node1="$(gnt-instance list --no-headers -o pnode "${target_name}")"
fi

if ! ssh "root@${node1}" "/bin/true"; then
  echo "Unable to reach ${node1} via SSH"
  exit 1
fi

read -p "Create VPS (y/n)?"
[ "$REPLY" == "y" ] || exit

# Sync files before we try and do anything.
/root/bin/sync-ganeti-files.sh > /dev/null

# Create the VM, but don't start it
gnt-instance add \
  -t "${ganeti_disk_type}" \
  -o "${ostype}" \
  -s "${disk_total}G" \
  -B memory="${ram_total}G" \
  -H kvm:vnc_bind_address=127.0.0.1 \
  ${gnt_node_assertion} \
  --net "0:link=${target_vlan}" \
  --no-start \
  --no-wait-for-sync \
  "${target_name}"

if [[ $? -eq 0 ]] ; then
  echo "INFO: Instance created"
else
  echo "ERROR: Ganeti failed to create the instance"
  exit 1
fi

cpu_count=$(calculate_cpu_count $shares)
if [ "${cpu_count}" -gt "${MAX_CPU_COUNT}" ]; then
  echo "WARNING: Clamping CPU count to max of ${MAX_CPU_COUNT}"
  cpu_count="${MAX_CPU_COUNT}"
fi

echo "INFO: Adding ${cpu_count} CPUs"
gnt-instance modify -B vcpus=${cpu_count} "${target_name}"

echo "INFO: Activating disks"

# Activate and target disk
gnt-instance activate-disks "${target_name}"

if [ "${add_only}" -ne 0 ] ; then
  echo "INFO: Install only, no tweaking"
  exit
fi

ssh "root@${node1}" "/root/bin/tweak-vps.sh -n ${target_name}"

if [[ $? -ne 0 ]] ; then
  echo "ERROR: Failed to tweak"
  exit 1
fi

echo "INFO: Staring VM for the first time."

gnt-instance startup "${target_name}"

echo "Waiting for startup"

sleep 5

echo "INFO: Tweaking off host kernel booting"

gnt-instance modify -H kernel_path="" "${target_name}"

echo "INFO: All done, should come back soon"

echo "INFO: Updating access controls"
/root/bin/sync-auth-keys.sh > /dev/null
