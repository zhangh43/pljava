#!/bin/bash -l

set -exo pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TOP_DIR=${CWDIR}/../../../
source "${TOP_DIR}/gpdb_src/concourse/scripts/common.bash"

function prepare_test(){

	cat > /home/gpadmin/test.sh <<-EOF
		set -exo pipefail
        if [ "$OSVER" == "suse11" ]; then
            # Official GPDB for SUSE 11 comes with very old version of glibc, getting rid of it here
            unset LD_LIBRARY_PATH
        fi
        source ${TOP_DIR}/gpdb_src/gpAux/gpdemo/gpdemo-env.sh
        source /usr/local/greenplum-db-devel/greenplum_path.sh

		gppkg -i pljava_bin/pljava-*.gppkg
        source /usr/local/greenplum-db-devel/greenplum_path.sh
        gpstop -arf
        pushd pljava_src
        if [ "$OSVER" == "suse11" ]; then
            #  suse outputs the time using GMT redhat uses UTC, added spaces to not
            #  change TIMEZONE=UTC in the expected file
            sed -i 's/ UTC/ GMT/g' gpdb/tests/expected/pljava_test.out
            sed -i 's/ UTC/ GMT/g' gpdb/tests/expected/pljava_test_optimizer.out
            #make test_all JAVA_HOME=/usr/lib64/jvm/java-1.6.0-openjdk-1.6.0 JAVA=/usr/lib64/jvm/java-1.6.0-openjdk-1.6.0/bin/java \
            #JAVAC=/usr/lib64/jvm/java-1.6.0-openjdk-1.6.0/bin/javac JAVAH=/usr/lib64/jvm/java-1.6.0-openjdk-1.6.0/bin/javah \
            #JAR=/usr/lib64/jvm/java-1.6.0-openjdk-1.6.0/bin/jar JAVADOC=/usr/lib64/jvm/java-1.6.0-openjdk-1.6.0/bin/javadoc
            make target_test
        else
            #make test_all JAVA_HOME=/usr/lib/jvm/java-1.6.0-openjdk.x86_64 JAVA=/usr/lib/jvm/java-1.6.0-openjdk.x86_64/bin/java \
            #JAVAC=/usr/lib/jvm/java-1.6.0-openjdk.x86_64/bin/javac JAVAH=/usr/lib/jvm/java-1.6.0-openjdk.x86_64/bin/javah \
            #JAR=/usr/lib/jvm/java-1.6.0-openjdk.x86_64/bin/jar JAVADOC=/usr/lib/jvm/java-1.6.0-openjdk.x86_64/bin/javadoc
            make target_test
        fi
        
        popd
	EOF

	chown -R gpadmin:gpadmin $(pwd)
	chown gpadmin:gpadmin /home/gpadmin/test.sh
	chmod a+x /home/gpadmin/test.sh

}

function test() {
	su gpadmin -c "bash /home/gpadmin/test.sh $(pwd)"

    mkdir -p pljava_gppkg

    case "$OSVER" in
        suse11)
        cp pljava_bin/pljava-*.gppkg pljava_gppkg/pljava-1.4.0-gp4-sles11-x86_64.gppkg
        echo "PL/Java test succeeded"
        ;;
        centos5)
        cp pljava_bin/pljava-*.gppkg pljava_gppkg/pljava-1.4.0-gp4-rhel5-x86_64.gppkg
        echo "PL/Java test succeeded"
        ;;
        *) echo "Unknown OS: $OSVER"; exit 1 ;;
    esac
}

function setup_gpadmin_user() {
    case "$OSVER" in
        suse*)
        ${TOP_DIR}/gpdb_src/concourse/scripts/setup_gpadmin_user.bash "sles"
        ;;
        centos*)
        ${TOP_DIR}/gpdb_src/concourse/scripts/setup_gpadmin_user.bash "centos"
        ;;
        *) echo "Unknown OS: $OSVER"; exit 1 ;;
    esac
}

function _main() {
	time install_gpdb
	time setup_gpadmin_user

    if [ "$OSVER" == "centos5" ]; then
        rm /home/gpadmin/.ssh/config
    fi

	time make_cluster
	time prepare_test
    time test

}

_main "$@"

