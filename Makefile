#-------------------------------------------------------------------------
# Copyright (c) 2004, 2005, 2006 TADA AB - Taby Sweden
# Distributed under the terms shown in the file COPYRIGHT
# found in the root folder of this project or at
# http://eng.tada.se/osprojects/COPYRIGHT.html
#
# @author Thomas Hallgren
#
# Top level Makefile for PLJava
#
# To compile a PLJava for PostgreSQL 8.x the makefile system will utilize
# the PostgreSQL pgxs system. The only prerequisite for such a compile is
# that a PostgreSQL 8.x is installed on the system and that the PATH is set
# so that the binaries of this installed can be executed.
#
#-------------------------------------------------------------------------

MODULE_big = pljava
PLJAVA_VER = 1.5.0
PLJAVA_PIVOTAL_VER = 1.4

PROJDIR = $(shell bash -c pwd)

PGXS = $(shell pg_config --pgxs)
include $(PGXS)

PLJAVADATA = $(DESTDIR)$(datadir)/pljava
PLJAVALIB  = $(DESTDIR)$(pkglibdir)/java

REGRESS_OPTS = --dbname=pljava_test --create-role=pljava_test
REGRESS = pljava

.DEFAULT_GOAL := build

.PHONY: build clean docs javadoc install uninstall depend release
	
build:
	mvn clean install
	cp $(PROJDIR)/pljava-so/target/nar/pljava-so-$(PLJAVA_VER)-amd64-Linux-gpp-plugin/lib/amd64-Linux-gpp/plugin/libpljava-so-$(PLJAVA_VER).so $(PROJDIR)/$(MODULE_big).so
	cp $(PROJDIR)/pljava/target/pljava-$(PLJAVA_VER).jar $(PROJDIR)/target/pljava.jar
	cp $(PROJDIR)/pljava-examples/target/pljava-examples-$(PLJAVA_VER).jar $(PROJDIR)/target/examples.jar

installdirs:
	$(MKDIR_P) '$(PLJAVALIB)'
	$(MKDIR_P) '$(PLJAVADATA)'
	$(MKDIR_P) '$(PLJAVADATA)/docs'

install: installdirs install-lib
	$(INSTALL_DATA) '$(PROJDIR)/pljava/target/pljava-$(PLJAVA_VER).jar'                   '$(PLJAVALIB)/pljava.jar'
	$(INSTALL_DATA) '$(PROJDIR)/pljava-examples/target/pljava-examples-$(PLJAVA_VER).jar' '$(PLJAVALIB)/examples.jar'
	$(INSTALL_DATA) '$(PROJDIR)/gpdb/installation/install.sql'                            '$(PLJAVADATA)'
	$(INSTALL_DATA) '$(PROJDIR)/gpdb/installation/uninstall.sql'                          '$(PLJAVADATA)'
	$(INSTALL_DATA) '$(PROJDIR)/gpdb/installation/examples.sql'                           '$(PLJAVADATA)'
	find $(PROJDIR)/docs -name "*.html" -exec $(INSTALL_DATA) {} '$(PLJAVADATA)/docs' \;

uninstall: uninstall-lib 
	rm -rf '$(PLJAVALIB)'
	rm -rf '$(PLJAVADATA)'
	
test:
	gpconfig -c pljava_classpath -v \'$(PROJDIR)/target/\'
	sed -i '/.* # PLJAVA.*/d' $(MASTER_DATA_DIRECTORY)/pg_hba.conf
	echo 'host    all      pljava_test   0.0.0.0/0    trust # PLJAVA' >> $(MASTER_DATA_DIRECTORY)/pg_hba.conf
	echo 'local   all      pljava_test                trust # PLJAVA' >> $(MASTER_DATA_DIRECTORY)/pg_hba.conf
	gpstop -u
	cd $(PROJDIR)/gpdb/tests && $(top_builddir)/src/test/regress/pg_regress $(REGRESS_OPTS) $(REGRESS)