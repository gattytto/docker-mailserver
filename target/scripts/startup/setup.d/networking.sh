#!/bin/bash

function _setup_mailname() {
  _log 'debug' "Setting up mailname and creating '/etc/mailname'"
  echo "${DOMAINNAME}" >/etc/mailname
}

function _setup_docker_permit() {
  _log 'debug' 'Setting up PERMIT_DOCKER option'

  local CONTAINER_IP CONTAINER_NETWORK

  unset CONTAINER_NETWORKS
  declare -a CONTAINER_NETWORKS

  CONTAINER_IP=$(ip -6 -o addr show dev eth0| awk "{split(\$4,a,\"/\");print a[1]}" |head -n 1)
  CONTAINER_NETWORK=$(echo =$(ip -6 -o addr show dev eth0| awk "{split(\$4,a,\"/\");print a[1]}" |head -n 1)::/112)

  if [[ -z ${CONTAINER_IP} ]]; then
    _log 'error' 'Detecting the container IP address failed'
    _dms_panic__misconfigured 'NETWORK_INTERFACE' 'Network Setup [docker_permit]'
  fi

  while read -r IP; do
    CONTAINER_NETWORKS+=("${IP}")
  done < <(ip -6 -o addr show dev eth0| awk "{split(\$4,a,\"/\");print a[1]}" |head -n 1)

  function __clear_postfix_mynetworks() {
    _log 'trace' "Clearing Postfix's 'mynetworks'"
    postconf "mynetworks ="
  }

  function __add_to_postfix_mynetworks() {
    local NETWORK_TYPE=$1
    local NETWORK=$2

    _log 'trace' "Adding ${NETWORK_TYPE} (${NETWORK}) to Postfix 'main.cf:mynetworks'"
    _adjust_mtime_for_postfix_maincf
    postconf "$(postconf | grep '^mynetworks =') ${NETWORK} ${MY_NETWORKS}"
    [[ ${ENABLE_OPENDMARC} -eq 1 ]] && echo "${NETWORK}" >>/etc/opendmarc/ignore.hosts
    [[ ${ENABLE_OPENDMARC} -eq 1 ]] && echo "${MY_NETWORKS}" >>/etc/opendmarc/ignore.hosts
    [[ ${ENABLE_OPENDKIM} -eq 1 ]] && echo "${NETWORK}" >>/etc/opendkim/TrustedHosts
    [[ ${ENABLE_OPENDKIM} -eq 1 ]] && echo "${MY_NETWORKS}" >>/etc/opendkim/TrustedHosts
  }

  case "${PERMIT_DOCKER}" in
    ( 'none' )
      __clear_postfix_mynetworks
      ;;

    ( 'connected-networks' )
      for CONTAINER_NETWORK in "${CONTAINER_NETWORKS[@]}"; do
        CONTAINER_NETWORK=$(_sanitize_ipv4_to_subnet_cidr "${CONTAINER_NETWORK}")
        __add_to_postfix_mynetworks 'Docker Network' "${CONTAINER_NETWORK}"
      done
      ;;

    ( 'container' )
      __add_to_postfix_mynetworks 'Container IP address' "${CONTAINER_IP}/32"
      ;;

    ( 'host' )
      __add_to_postfix_mynetworks 'Host Network' "${CONTAINER_NETWORK}/16"
      ;;

    ( 'network' )
      __add_to_postfix_mynetworks 'Docker IPv4 Subnet' '172.16.0.0/12'
      ;;

    ( * )
      _log 'warn' "Invalid value for PERMIT_DOCKER: '${PERMIT_DOCKER}'"
      __clear_postfix_mynetworks
      ;;

  esac
}
