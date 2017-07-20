#!/bin/bash

set -x
set -e


if [ "$OSVER" == "centos5" ]; then
    rm -f /usr/bin/python && ln -s /usr/bin/python26 /usr/bin/python
fi

if [ "$OSVER" == "suse11" ]; then
    wget http://www-us.apache.org/dist/maven/maven-3/3.5.0/binaries/apache-maven-3.5.0-bin.tar.gz
    tar -zxf apache-maven-3.5.0-bin.tar.gz
    pushd apache-maven-3.5.0
    export MAVEN_HOME=$(pwd)
    export PATH=$MAVEN_HOME/bin:$PATH
    popd
    mvn -v
    [ '$?' ne '0' ] && exit 1
fi

mkdir /usr/local/greenplum-db-devel
tar zxf bin_gpdb/bin_gpdb.tar.gz -C /usr/local/greenplum-db-devel
source /usr/local/greenplum-db-devel/greenplum_path.sh

pushd pljava_src
make clean
make
mvn dependency:go-offline
popd

source pljava_src/concourse/scripts/mvn_utils.sh
mvn_repo_save $OSVER
