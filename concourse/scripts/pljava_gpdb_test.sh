#!/bin/bash

set -x

WORKDIR=`pwd`

GPDBBIN=$1
PLJAVABIN=$2
OSVER=$3
GPHDFS=$4
TMPDIR=/tmp/localplccopy

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
setup_gpadmin_user
setup_sshd

# GPDB Installation
cp pljava_src/concourse/scripts/*.sh /tmp
chmod 777 /tmp/*.sh
runuser gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh && bash /tmp/gpdb_install.sh /data" || exit 1

# Installing PL/Java and running tests
runuser gpadmin -c "bash /tmp/pljava_install_test.sh $PLJAVABIN $OSVER $WORKDIR $TMPDIR"
RETCODE=$?

if [ $RETCODE -ne 0 ]; then
    echo "PL/Container test failed"
    echo "====================================================================="
    echo "========================= REGRESSION DIFFS =========================="
    echo "====================================================================="
    cat $TMPDIR/tests/regression.out
    cat $TMPDIR/tests/regression.diffs
    echo "====================================================================="
    echo "============================== RESULTS =============================="
    echo "====================================================================="
    cat $TMPDIR/tests/results/plcontainer_test_python.out
    cat $TMPDIR/tests/results/plcontainer_test_anaconda.out
    cat $TMPDIR/tests/results/plcontainer_test_r.out
else
    echo "PL/Container test succeeded"
fi

stop_docker || exit 1

exit $RETCODE