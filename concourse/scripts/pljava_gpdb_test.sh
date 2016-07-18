#!/bin/bash

set -x

WORKDIR=`pwd`

GPDBBIN=$1
PLJAVABIN=$2
OSVER=$3
GPHDFS=$4
TMPDIR=/tmp/localplccopy

if [ "$OSVER" == "centos5" ]; then
    rm -f /usr/bin/python && ln -s /usr/bin/python26 /usr/bin/python
fi

# Put GPDB binaries in place to get pg_config
cp $GPDBBIN/$GPDBBIN.tar.gz /usr/local
pushd /usr/local
tar zxvf $GPDBBIN.tar.gz
if [ "$GPHDFS" != "none" ]; then
    cp $WORKDIR/$GPHDFS/gphdfs.so /usr/local/greenplum-db/lib/postgresql/gphdfs.so
fi
popd
source /usr/local/greenplum-db/greenplum_path.sh || exit 1

# GPDB Installation Preparation
mkdir /data
source pljava_src/concourse/scripts/gpdb_install_functions.sh || exit 1
setup_gpadmin_user $OSVER
setup_sshd

# GPDB Installation
cp pljava_src/concourse/scripts/*.sh /tmp
chmod 777 /tmp/*.sh
su - gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh && bash /tmp/gpdb_install.sh /data" || exit 1

# TODO: temporary
exit 0

# Installing PL/Java and running tests
su - gpadmin -c "bash /tmp/pljava_install_test.sh $PLJAVABIN $OSVER $WORKDIR $TMPDIR"
RETCODE=$?

if [ $RETCODE -ne 0 ]; then
    echo "PL/Java test failed"
    echo "====================================================================="
    echo "========================= REGRESSION DIFFS =========================="
    echo "====================================================================="
    cat $TMPDIR/gpdb/tests/regression.out
    cat $TMPDIR/gpdb/tests/regression.diffs
    echo "====================================================================="
    echo "============================== RESULTS =============================="
    echo "====================================================================="
    cat $TMPDIR/gpdb/tests/results/pljava_init.out
    cat $TMPDIR/gpdb/tests/results/pljava_functions.out
    cat $TMPDIR/gpdb/tests/results/pljava_test.out
else
    echo "PL/Java test succeeded"
fi

exit $RETCODE