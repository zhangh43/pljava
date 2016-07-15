#!/bin/bash

set -x
set -e

GPDBBIN=$1
OSVER=$3

if [ "$OSVER" == "centos5" ]; then
    rm -f /usr/bin/python && ln -s /usr/bin/python26 /usr/bin/python
fi

cp $GPDBBIN/$GPDBBIN.tar.gz /usr/local
pushd /usr/local
tar zxvf $GPDBBIN.tar.gz
popd
source /usr/local/greenplum-db/greenplum_path.sh

pushd pljava_src
make clean
make
mvn dependency:go-offline
popd

source pljava_src/concourse/scripts/mvn_scripts.sh
mvn_repo_save $OSVER