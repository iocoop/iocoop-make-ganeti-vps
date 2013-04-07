#!/bin/bash
#
# Author: Ben Kochie <ben@nerp.net>
#
# Tweak VPS after creation

# Where to get patchs/files from
SRC="/root/make-vps"

# URL to get to the API
API_URL="https://cloud.cernio.com:5080/2"

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
  gnt-node list --no-headers | awk '{print $1" "$7" "$8}' | sed 's/\.[a-z.]* / /'
}

get_nodes_disk() {
  gnt-node list --no-headers --output="name,dfree" | sed 's/\.[a-z.]* / / ; s/G$//'
}

vlan_info() {
  ip="$1"
  subnet=$(echo "${ip}" | cut -f1-3 -d'.')
  host=$(echo "${ip}" | cut -f4 -d'.')

  case ${subnet} in
    # MSP01
    204.246.122)
      if [ "${host}" -ge 1 -a "${host}" -le 13 ] ; then
        vlan="virbr0"
        netmask="255.255.255.240"
        gateway="204.246.122.14"
      elif [ "${host}" -ge 17 -a "${host}" -le 29 ] ; then
        vlan="virbr1006"
        netmask="255.255.255.240"
        gateway="204.246.122.30"
      elif [ "${host}" -ge 65 -a "${host}" -le 125 ] ; then
        vlan="virbr1004"
        netmask="255.255.255.192"
        gateway="204.246.122.126"
      elif [ "${host}" -ge 129 -a "${host}" -le 189 ] ; then
        vlan="virbr1007"
        netmask="255.255.255.192"
        gateway="204.246.122.190"
      else
        echo "ERROR: Subnet ${subnet} host ${host} has no vlan"
        return 1
      fi
    ;;
    # MTV01
    66.109.99)
      if [ "${host}" -ge 1 -a "${host}" -le 125 ] ; then
        vlan="virbr3001"
        netmask="255.255.255.128"
        gateway="66.109.99.126"
      elif [ "${host}" -ge 161 -a "${host}" -le 173 ] ; then
        vlan="virbr3004"
        netmask="255.255.255.240"
        gateway="66.109.99.174"
      elif [ "${host}" -ge 177 -a "${host}" -le 253 ] ; then
        vlan="virbr3005"
        netmask="255.255.255.192"
        gateway="66.109.99.254"
      else
        echo "ERROR: Subnet ${subnet} host ${host} has no vlan"
        return 1
      fi
    ;;
    *) echo "ERROR: Subnet ${subnet} not supported"
       return 1
    ;;
  esac
  echo "target_vlan='${vlan}'"
  echo "target_netmask='${netmask}'"
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
