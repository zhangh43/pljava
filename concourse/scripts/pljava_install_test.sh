#!/bin/bash

source ~/.bashrc

set -x

PLJAVABIN=$1
OSVER=$2
WORKDIR=$3
TMPDIR=$4

cd $WORKDIR

# Install PL/Container package
gppkg -i $PLJAVABIN/pljava-$OSVER.gppkg || exit 1

rm -rf $TMPDIR
cp -r pljava_src $TMPDIR
cd $TMPDIR
if [ "$OSVER" == "suse11" ]; then
#  suse outputs the time using GMT redhat uses UTC, added spaces to not
#  change TIMEZONE=UTC in the expected file
    sed -i 's/ UTC/ GMT/g' /tmp/localplccopy/gpdb/tests/expected/pljava_test.out
fi
make targetcheck || exit 1
