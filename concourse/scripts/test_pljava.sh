#!/bin/bash

set -x

WORKDIR=`pwd`
TMPDIR=/tmp/localplccopy

if [ "$OSVER" == "centos5" ]; then
    rm -f /usr/bin/python && ln -s /usr/bin/python26 /usr/bin/python
fi

# Put GPDB binaries in place to get pg_config
mkdir /usr/local/greenplum-db-devel
tar zxf bin_gpdb/bin_gpdb.tar.gz -C /usr/local/greenplum-db-devel
source /usr/local/greenplum-db-devel/greenplum_path.sh || exit 1

if [ "$OSVER" == "suse11" ]; then
    export LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64:/lib:/lib64
    zypper addrepo --no-gpgcheck http://download.opensuse.org/distribution/11.4/repo/oss/ oss
    zypper refresh
    zypper --no-gpg-checks -n install libopenssl-devel openssl
fi

# GPDB Installation Preparation
mkdir /data
source pljava_src/concourse/scripts/release_gpdb_install_functions.sh || exit 1
setup_gpadmin_user $OSVER
setup_sshd

# GPDB Installation
cp pljava_src/concourse/scripts/*.sh /tmp
chmod 777 /tmp/*.sh
su - gpadmin -c "source $GPHOME/greenplum_path.sh && bash /tmp/release_gpdb_install.sh /data" || exit 1

# Installing PL/Java and running tests
su - gpadmin -c "bash /tmp/release_pljava_install_test.sh pljava_bin $OSVER $WORKDIR $TMPDIR"
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
    mkdir -p pljava_gppkg
    ls pljava_bin/pljava-*-untest.gppkg | sed 's/-untest.gppkg/.gppkg/g' | xargs cp pljava_bin/pljava-*-untest.gppkg
    rm pljava_bin/pljava-*-untest.gppkg
    cp pljava_bin/pljava-*.gppkg pljava_gppkg
    echo "PL/Java test succeeded"
fi

exit $RETCODE
