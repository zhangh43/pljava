#!/bin/bash

set -euxo pipefail

can_add_user_to_group_in_centos_way() {
  # for example, the GPDB setup scripts use this, and treat centos differently
  local username=redpear_demigod
  local groupname=powerful_people
  /usr/sbin/useradd $username
  groupadd $groupname
  usermod -a -G $groupname $username
}

installed_wget() {
  which wget
}

# When this does not match, ivy files need to be updated as well as this test.
check_centos_version() {
  local expected_version="5.11"
  cat /etc/issue | head -n1 | grep $expected_version
}

_main() {
  check_centos_version
  can_add_user_to_group_in_centos_way
  installed_wget
}

_main
