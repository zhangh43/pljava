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

if [ "$OSVER" == "suse11" ]; then
    export LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64:/lib:/lib64
    zypper addrepo http://download.opensuse.org/distribution/11.4/repo/oss/ oss
    zypper --no-gpg-checks -n install libopenssl-devel openssl
fi

pushd pljava_src
make clean
make
pushd gpdb/packaging
make cleanall && make
ls pljava-*.gppkg | sed 's/.gppkg/-untest.gppkg/g' | xargs cp pljava-*.gppkg
popd
popd

mkdir -p pljava_gppkg
cp pljava_src/gpdb/packaging/pljava-*-untest.gppkg pljava_gppkg
