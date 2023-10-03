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
usage $(basename $0) -h [-a] -n <hostname> -s <size> -o <ostype> -d <extra_disk_shares>
  -a    Add only, don't startup and tweak
  -d    Extra disk shares of size ${SHARE_DISK_SIZE}G
  -n    The hostname for the instance (must resolve)
  -i    IP address
  -o    OS Type (${os_list})
  -p    Primary Node (${node_list})
  -s    Number of shares (1-8) ${SHARE_RAM_SIZE}G ram / ${SHARE_DISK_SIZE}G disk
  -f    Freshbooks recurring profile ID
  -e    Email address of the user (as recorded in the IP address Google Sheet)
  -k    SSH key string (e.g. "ssh-rsa AAAA..... user@example.com")
USAGE
}

declare -i OPTIND=1 help=0 add_only=0
declare opt="" optarg="" target_name="" ostype="" node1=""
while getopts 'ad:hn:i:o:p:s:f:e:k:' opt ; do
  case ${opt} in
    a) add_only=1 ;;
    d) extra_disk="${OPTARG}" ;;
    h) help=1 ;;
    n) target_name="${OPTARG}" ;;
    i) target_ip="${OPTARG}" ;;
    o) ostype="${OPTARG}" ;;
    p) node1="${OPTARG}" ;;
    s) shares="${OPTARG}" ;;
    f) freshbooks_id="${OPTARG}" ;;
    e) email="${OPTARG}" ;;
    k) key_content="${OPTARG}" ;;
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

while [[ -z "${target_name}" ]] ; do
  read -p "Enter the VPS hostname to create: " target_name
  target_test=$(gnt-instance list "${target_name}" 2> /dev/null | tail -n+2 | awk '{print $1}')
  if [[ -n "${target_test}" ]] ; then
    unset target_name
    echo "ERROR: '${target_name}' already exists"
  fi
done

while [[ -z "${target_ip}" ]] ; do
  read -p "Enter the VPS IP address to use: " target_ip
  if [[ ! "${target_ip}" =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then
    echo "ERROR: ${target_ip} isn't a valid IP address"
    continue
  fi
  if test_hosts_entry "${target_ip}" "${target_name}"; then
    echo "There is an existing entry for this IP in /etc/hosts."
    echo "This likely indicates that it previously belonged to a different VPS that was torn down but not cleaned up or that the IP database is out of date."
    echo "Please remove this IP from /etc/hosts if it is indeed free before continuing"
    exit 1
  fi
done

echo "${target_ip} ${target_name}" >>/etc/hosts

if [[ -z "$(getent ahostsv4 "${target_name}" | awk '{print $1}' | head -n1)" ]] ; then
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
  while [[ -z "${key_content}" || -z "${email}" ]]; do
    read -p "Enter the user's email address that was entered in the IP address Google Sheet: " email
    read -p "Enter the user's SSH public key: " key_content
  done
  key_content="$(echo "${key_content}" | awk '{print $1" "$2}') ${email}"
  echo "${key_content}" > "${target_keyfile}"
fi

test_ssh_keyfile "${target_keyfile}" || exit 1

while [[ -z "${shares}" || "${shares}" -lt 1 || "${shares}" -gt 8 ]] ; do
  read -p "Enter the number of shares to allocate to the VPS (1-8): " shares
done

if [[ -z "${extra_disk}" || "${extra_disk}" -lt 0 || "${extra_disk}" -gt 8 ]] ; then
  read -p "Enter the number of extra disk shares (${SHARE_DISK_SIZE}GB each) to allocate to the VPS (0-8): " extra_disk
fi

ostype=$(echo ${os_list} | fmt -1 | awk -v "os=${ostype}" '$1 == os')
while [[ -z "${ostype}" ]]; do
  echo "${os_list}"
  read -p "Enter the OS to install from the list above: " ostype
  ostype=$(echo ${os_list} | fmt -1 | awk -v "os=${ostype}" '$1 == os')
done

# The json_read returns "True" not "true" because the function returns a a Python variable not a JSON variable.
# Here we convert the value to all lower case to avoid issues related to case
if [[ "$(json_read /etc/make-vps.json balance_on_free_space | tr '[:upper:]' '[:lower:]')" = "true" ]] ; then
  if [[ -z "${node1}" ]] ; then
    node1=$(get_nodes_disk | sort -rn -k2 | head -n1 | awk '{print $1}')
  fi
  node2=$(get_nodes_disk | sort -rn -k2 | grep -v "${node1}" | head -n1 | awk '{print $1}')
  gnt_node_assertion="-n ${node1}:${node2}"
fi

ganeti_disk_type="$(json_read /etc/make-vps.json ganeti_disk_type)"
if [[ -z "${ganeti_disk_type}" ]] ; then
  echo "ERROR: No ganeti_disk_type found in /etc/make-vps.json"
  exit 1
fi

ram_total=$((shares * SHARE_RAM_SIZE))
disk_total=$(((extra_disk + shares) * SHARE_DISK_SIZE))

while [[ -z "${freshbooks_id}" ]]; do
  read -p "Enter the Freshbooks recurring profile ID: " freshbooks_id
done

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
Freshbooks recurring profile ID: ${freshbooks_id}
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

echo "INFO: Tagging ${target_name} with the freshbooks-recurring-profile-id of ${freshbooks_id}"
gnt-instance add-tags "${target_name}" "freshbooks-recurring-profile-id:${freshbooks_id}"

echo "While the VPS is provisioned, you can watch the console by running"
echo "gnt-instance console $target_name"
echo "The VPS will provision, then power off, briefly entering an ERROR_down state, boot again and eventually drop to a login prompt"
