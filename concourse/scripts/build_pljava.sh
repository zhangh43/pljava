#!/bin/bash

set -ex

if [ "$OSVER" == "centos5" ]; then
    rm -f /usr/bin/python && ln -s /usr/bin/python26 /usr/bin/python
fi

mkdir /usr/local/greenplum-db-devel
tar zxf bin_gpdb/bin_gpdb.tar.gz -C /usr/local/greenplum-db-devel
source /usr/local/greenplum-db-devel/greenplum_path.sh

# extract jre.
mkdir /opt/jre
tar zxf jre/jre-1.6.0_32.tgz -C /opt/jre

pushd pljava_src
make clean
make
pushd gpdb/packaging
export PL_GP_VERSION=$PL_GP_VERSION
make cleanall && make
popd
popd

mkdir -p pljava_gppkg
cp pljava_src/gpdb/packaging/pljava-*.gppkg pljava_gppkg
