#!/bin/bash

source ~/.bashrc

set -x

PLJAVABIN=$1
OSVER=$2
WORKDIR=$3
TMPDIR=$4

cd $WORKDIR

# Install PL/Container package
gppkg -i $PLJAVABIN/pljava-*.gppkg || exit 1

# Ensure that the JVM is reporting time/dates in UTC to avoid
# failures during testing (SuSE reports GMT instead of UTC)



rm -rf $TMPDIR
cp -r pljava_src $TMPDIR
cd $TMPDIR
if [ "$OSVER" == "sles11" ]; then
#  suse outputs the time using GMT redhat uses UTC, added spaces to not
#  change TIMEZONE=UTC in the expected file
    sed -i 's/ UTC/ GMT/g' /tmp/localplccopy/gpdb/tests/expected/pljava_test.out
    sed -i 's/ UTC/ GMT/g' /tmp/localplccopy/gpdb/tests/expected/pljava_test_optimizer.out
fi
make targetcheck || exit 1
