#!/bin/bash

set -x

WORKDIR=`pwd`
TMPDIR=/tmp/localplccopy

function install_openssl(){
    pushd /opt
    wget --no-check-certificate https://www.openssl.org/source/openssl-1.0.2l.tar.gz
    wget --no-check-certificate https://www.openssl.org/source/openssl-fips-2.0.16.tar.gz
    wget --no-check-certificate https://mirror.aarnet.edu.au/pub/OpenBSD/OpenSSH/portable/openssh-6.9p1.tar.gz
    tar -zxf openssl-1.0.2l.tar.gz
    tar -zxf openssl-fips-2.0.16.tar.gz
    tar -zxf openssh-6.9p1.tar.gz

    pushd openssl-fips-2.0.16
    ./config
    make && make install
    popd
    pushd openssl-1.0.2l
    ./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl/ssl shared fips enable-ssl2
    make depend
    make && make install
    popd

    cp -r /usr/local/ssl/fips-2.0/include/openssl/fips*.h /usr/local/ssl/include/openssl/
    rm -r /usr/local/ssl/fips-2.0

    rpm -qa | grep openssh | rpm -e {} --nodeps
    pushd openssh-6.9p1
    ./configure --prefix=/usr/ --sysconfdir=/etc/ssh --with-zlib --with-ssl-dir=/usr/local/ssl --with-md5-passwords mandir=/usr/share/man
    make && make install
    cp contrib/suse/rc.sshd /etc/init.d/sshd
    chmod +x /etc/init.d/sshd
    cp -f -r sshd_config /etc/ssh/sshd_config
    cp -f -r sshd /usr/sbin/sshd
    cp -f -r ssh /usr/bin/ssh
    /etc/init.d/sshd restart
    popd

    popd

}
if [ "$OSVER" == "centos5" ]; then
    rm -f /usr/bin/python && ln -s /usr/bin/python26 /usr/bin/python
fi

# Put GPDB binaries in place to get pg_config
mkdir /usr/local/greenplum-db-devel
tar zxf bin_gpdb/bin_gpdb.tar.gz -C /usr/local/greenplum-db-devel
source /usr/local/greenplum-db-devel/greenplum_path.sh || exit 1

if [ "$OSVER" == "suse11" ]; then
    install_openssl
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
    cp pljava_bin/pljava-*.gppkg pljava_gppkg
    echo "PL/Java test succeeded"
fi

exit $RETCODE
