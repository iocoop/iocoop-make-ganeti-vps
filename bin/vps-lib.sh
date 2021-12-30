#!/bin/bash
#
# Author: Ben Kochie <ben@nerp.net>
#
# Tweak VPS after creation

# Where to get patchs/files from
SRC="/root/make-vps"

json_read() {
  file=$1
  var=$2
  python -c "import json; import sys; print json.loads(sys.stdin.read())['${var}']" < "${file}"
}

get_instance_info() {
  target_name="$1"
  tmpfile=$(mktemp)
  curl -s -k "${API_URL}/instances/${target_name}" > "${tmpfile}"
  echo "${tmpfile}"
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
      expected_api_host="g0-cluster.iocoop.org"
      if [ "${host}" -ge 1 -a "${host}" -le 13 ] ; then
        vlan="virbr1000"
        netmask="255.255.255.240"
        netmask_number="28"
        gateway="204.246.122.14"
        v6_subnet="2602:ff06:677:0"
      elif [ "${host}" -ge 17 -a "${host}" -le 29 ] ; then
        vlan="virbr1006"
        netmask="255.255.255.240"
        netmask_number="28"
        gateway="204.246.122.30"
        v6_subnet="2602:ff06:677:6"
      elif [ "${host}" -ge 65 -a "${host}" -le 125 ] ; then
        vlan="virbr1004"
        netmask="255.255.255.192"
        netmask_number="26"
        gateway="204.246.122.126"
        v6_subnet="2602:ff06:677:4"
      elif [ "${host}" -ge 129 -a "${host}" -le 189 ] ; then
        vlan="virbr1007"
        netmask="255.255.255.192"
        netmask_number="26"
        gateway="204.246.122.190"
        v6_subnet="2602:ff06:677:7"
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
        v6_subnet="2602:ff06:725:1"
      elif [ "${host}" -ge 177 -a "${host}" -le 253 ] ; then
        vlan="virbr3005"
        netmask="255.255.255.192"
        netmask_number="26"
        gateway="216.252.162.254"
        v6_subnet="2602:ff06:725:5"
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

  # Calculate IPv6 info from target.
  target_v6_octet="$(printf "%x" $(echo "${target_ip}" | cut -f4 -d.))"
  target_v6_ip="${target_v6_subnet}:${target_v6_octet}::1"
  target_v6_gateway="${target_v6_subnet}::1"

  echo "target_vlan='${vlan}'"
  echo "target_netmask='${netmask}'"
  echo "target_netmask_number='${netmask_number}'"
  echo "target_gateway='${gateway}'"
  echo "target_v6_ip='${target_v6_ip}'"
  echo "target_v6_gateway='${target_v6_gateway}'"
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

# URL to get to the API
export GANETI_AUTH="$(json_read /etc/make-vps.json ganeti_auth)"
export API_HOST="$(json_read /etc/make-vps.json ganeti_instance)"
export API_URL="https://${GANETI_AUTH:+${GANETI_AUTH}@}$API_HOST/2"
