#!/bin/bash

set -x
set -e

GPDBBIN=$1
OUTPUT=$2
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
pushd gpdb/packaging
make cleanall && make
popd
popd

cp pljava_src/gpdb/packaging/pljava-*.gppkg $OUTPUT/