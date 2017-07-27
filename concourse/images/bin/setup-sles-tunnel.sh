#!/bin/bash

SLES_ZYPPER_ENDPOINT=sles11sp4.pivotalci.info
KEY_FILE=$HOME/workspace/ci-infrastructure/deployments/toolsmiths-bosh/concourse-bosh-key.pem

function open_tunnel {

  if nc -z localhost 80; then
    echo "Port 80 is currently being used."
    exit 1
  fi

  # BG the ssh tunnel
  sudo ssh  -fN -o ServerAliveInterval=30 -i $KEY_FILE -L 0.0.0.0:80:$SLES_ZYPPER_ENDPOINT:80 vcap@pa-toolsmiths.bosh.pivotalci.info

  if [ ! $? -eq 0 ] ; then
    echo "ssh command failed."
    exit 1
  fi

  echo "SSH Tunnel to $SLES_ZYPPER_ENDPOINT is open at localhost:80."
}

function add_hostfile_entry {
  ip=$(ifconfig | grep "inet " | grep -Fv 127.0.0.1 | awk '{print $2}')

  if grep -q $SLES_ZYPPER_ENDPOINT /etc/hosts ; then
    echo "Hostfile entry for $SLES_ZYPPER_ENDPOINT found in /etc/hosts"
    exit 1
  fi

  # SSH tunnel is for localhost, therefore add hostfile entry based on local ip
  echo "${ip} $SLES_ZYPPER_ENDPOINT" | sudo tee -a /etc/hosts >/dev/null

}

function main {
  open_tunnel
  add_hostfile_entry
}

main
