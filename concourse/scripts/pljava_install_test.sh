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

make targetcheck || exit 1