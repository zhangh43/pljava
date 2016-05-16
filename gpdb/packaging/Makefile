all: gppkg

PGXS := $(shell pg_config --pgxs)
include $(PGXS)

OS=$(word 1,$(subst _, ,$(BLD_ARCH)))
ARCH=$(shell uname -p)

PLJAVA_DIR=`cd ../.. && pwd`
PLJAVA_PIVOTAL_VER=1.4
PLJAVA_PIVOTAL_RELEASE=0
PLJAVA_OSS_VER=1.5.0
PLJAVA_GPPKG_VER=ossv$(PLJAVA_OSS_VER)_pv$(PLJAVA_PIVOTAL_VER).$(PLJAVA_PIVOTAL_RELEASE)_gpdb4.3orca
PLJAVA_RPM_FLAGS="--define 'pljava_dir $(PLJAVA_DIR)' --define 'pljava_ver $(PLJAVA_PIVOTAL_VER)' --define 'pljava_rel $(PLJAVA_PIVOTAL_RELEASE)'"
PLJAVA_RPM=pljava-$(PLJAVA_PIVOTAL_VER)-$(PLJAVA_PIVOTAL_RELEASE).$(ARCH).rpm
PLJAVA_GPPKG=pljava-$(PLJAVA_GPPKG_VER)-$(OS)-$(ARCH).gppkg

TARGET_GPPKG=$(PLJAVA_GPPKG)
EXTRA_CLEAN+=$(PLJAVA_RPM) $(PLJAVA_GPPKG)

#
# Generic rules to build gppkgs included here
#
include gppkg.mk

.PHONY: gppkg
gppkg: clean
	$(MAKE) $(PLJAVA_RPM) RPM_FLAGS=$(PLJAVA_RPM_FLAGS)
	$(MAKE) $(PLJAVA_GPPKG) MAIN_RPM=$(PLJAVA_RPM)

.PHONY: cleanall
cleanall: clean
	rm -rf BUILDROOT
	rm -rf SOURCES
	rm -rf SRPMS
	rm -rf $(PLJAVA_RPM)
	rm -rf $(PLJAVA_GPPKG)