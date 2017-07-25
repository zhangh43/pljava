#!/bin/bash

set -x
set -e


if [ "$OSVER" == "centos5" ]; then
    rm -f /usr/bin/python && ln -s /usr/bin/python26 /usr/bin/python
fi

mkdir /usr/local/greenplum-db-devel
tar zxf bin_gpdb/bin_gpdb.tar.gz -C /usr/local/greenplum-db-devel
source /usr/local/greenplum-db-devel/greenplum_path.sh

source pljava_src/concourse/scripts/mvn_utils.sh
mvn_repo_install $OSVER

pushd pljava_src
make clean
make
pushd gpdb/packaging
make cleanall && make
popd
popd

mkdir -p pljava_gppkg
cp pljava_src/gpdb/packaging/pljava-*.gppkg pljava_gppkg
