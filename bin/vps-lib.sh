#!/bin/bash
#
# Author: Ben Kochie <ben@nerp.net>
#
# Tweak VPS after creation

# Where to get patches/files from
SRC="/root/make-vps"

json_read() {
  file=$1
  var=$2
  jq -r ".${var}" < "${file}"
}

calculate_cpu_count() {
  local shares
  shares="$1"
  echo $(( (shares + 1) /2 ))
}

get_instance_info() {
  target_name="$1"
  tmpfile="$(mktemp)"
  echo "${tmpfile}"
  curl --silent --insecure --fail "${API_URL}/instances/${target_name}" > "${tmpfile}"
}

get_nodes() {
  gnt-node list --no-headers --output="name"
}

get_nodes_disk() {
  gnt-node list --no-headers --units=m --output="name,dfree" | sed 's/\.[a-z.]* / /'
}

vlan_info() {
  ip="$1"
  subnet=$(echo "${ip}" | cut -f1-3 -d'.')
  host=$(echo "${ip}" | cut -f4 -d'.')

  case ${subnet} in
    # MSP01
    204.246.122)
      expected_api_host="g0.iocoop.org"
      if [ "${host}" -ge 1 -a "${host}" -le 13 ] ; then
        vlan="virbr1000"
        netmask="255.255.255.240"
        netmask_number="28"
        gateway="204.246.122.14"
      elif [ "${host}" -ge 17 -a "${host}" -le 29 ] ; then
        vlan="virbr1006"
        netmask="255.255.255.240"
        netmask_number="28"
        gateway="204.246.122.30"
      elif [ "${host}" -ge 65 -a "${host}" -le 125 ] ; then
        vlan="virbr1004"
        netmask="255.255.255.192"
        netmask_number="26"
        gateway="204.246.122.126"
      elif [ "${host}" -ge 129 -a "${host}" -le 189 ] ; then
        vlan="virbr1007"
        netmask="255.255.255.192"
        netmask_number="26"
        gateway="204.246.122.190"
      else
        echo "ERROR: Subnet ${subnet} host ${host} has no vlan"
        return 1
      fi
    ;;
    # SCL01
    216.252.162)
      expected_api_host="g1-cluster.iocoop.org"
      if [ "${host}" -ge 1 -a "${host}" -le 125 ] ; then
        vlan="virbr3001"
        netmask="255.255.255.128"
        netmask_number="25"
        gateway="216.252.162.126"
      elif [ "${host}" -ge 177 -a "${host}" -le 253 ] ; then
        vlan="virbr3005"
        netmask="255.255.255.192"
        netmask_number="26"
        gateway="216.252.162.254"
      else
        echo "ERROR: Subnet ${subnet} host ${host} has no vlan"
        return 1
      fi
    ;;
    216.252.163)
      expected_api_host="g1-cluster.iocoop.org"
      if [ "${host}" -ge 1 -a "${host}" -le 125 ] ; then
        vlan="virbr3006"
        netmask="255.255.255.128"
        netmask_number="25"
        gateway="216.252.163.126"
      else
        echo "ERROR: Subnet ${subnet} host ${host} has no vlan"
        return 1
      fi
    ;;
    *) echo "ERROR: Subnet ${subnet} not supported"
       return 1
    ;;
  esac
  if [[ "${API_HOST}" == "${API_HOST#${expected_api_host}}" ]] ; then
    echo "ERROR: Wrong VPS IP address for this cluster. ${ip} is in VLAN ${vlan} which doesn't exist in ${expected_api_host}"
    return 1
  fi

  echo "target_vlan='${vlan}'"
  echo "target_netmask='${netmask}'"
  echo "target_netmask_number='${netmask_number}'"
  echo "target_gateway='${gateway}'"
}

test_ssh_keyfile() {
  file="$1"
  if [ ! -s "${file}" ] ; then
    echo "ERROR: Invalid ssh keyfile '${file}'"
    return 1
  fi
  while read line ;do
    ${SRC}/bin/test-ssh-key.py "${line}"
    if [ $? != 0 ] ; then
      echo "ERROR: found invalid ssh key"
      return 1
    fi
  done < "${file}"
}

check_for_bins() {
  type curl >/dev/null 2>&1 || ( echo "ERROR: curl binary is missing" && return 1 )
  type jq >/dev/null 2>&1 || ( echo "ERROR: jq binary is missing" && return 1 )
  type gnt-node >/dev/null 2>&1 || ( echo "ERROR: gnt-node binary is missing" && return 1 )
  type sed >/dev/null 2>&1 || ( echo "ERROR: sed binary is missing" && return 1 )
  type cut >/dev/null 2>&1 || ( echo "ERROR: cut binary is missing" && return 1 )
  type "${SRC}/bin/test-ssh-key.py" >/dev/null 2>&1 || ( echo "ERROR: ${SRC}/bin/test-ssh-key.py binary is missing" && return 1 )
  return 0
}

test_hosts_entry() {
  host_ip="$1"
  host_name="$2"
  if [[ $# -ne 2 ]] ; then
    echo "usage: ${FUNCNAME[0]} <IP> <hostname>"
    return 1
  fi
  while read -r line ; do
    check_ip=$(awk '{print $1}' <(echo "${line}"))
    if [[ "${host_ip}" == "${check_ip}" ]] ; then
      if ! grep -q "${host_name}" <(echo "${line}") ; then
        echo "ERROR: Found miss-matching host in /etc/hosts: ${line}"
        return 1
      fi
    fi
  done < /etc/hosts
  return 0
}

# URL to get to the API
export GANETI_AUTH="$(json_read /etc/make-vps.json ganeti_auth)"
export API_HOST="$(json_read /etc/make-vps.json ganeti_instance)"
export API_URL="https://${GANETI_AUTH:+${GANETI_AUTH}@}$API_HOST/2"
