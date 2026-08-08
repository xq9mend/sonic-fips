.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -euo pipefail

ARCH ?= amd64
SRC_PATH = src
RULES_PATH = rules
TARGET_PATH ?= target
ROOT := $(shell pwd)
DEST = $(ROOT)/$(TARGET_PATH)

QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"
.SECONDEXPANSION:

include $(RULES_PATH)/*.mk

# Export environments
export SYMCRYPT_OPENSSL_VERSION
export QUILT_REFRESH_ARGS
export ARCH
export DEST

MAIN_TARGET_LIST = $(addprefix $(TARGET_PATH)/, $(MAIN_TARGETS))

all: $(MAIN_TARGET_LIST)

list:
	@$(foreach target,$(MAIN_TARGET_LIST),echo $(target);)

symcrypt : $(TARGET_PATH)/$(SYMCRYPT_OPENSSL)

openssl: $(TARGET_PATH)/$(OPENSSL)

$(addprefix $(TARGET_PATH)/, $(MAIN_TARGETS)) : $(TARGET_PATH)/% : $$(addprefix $(TARGET_PATH)/,$$($$*_DEPENDS))
	# Remove target to force rebuild
	rm -f $(addprefix $(TARGET_PATH)/, $*)
	mkdir -p $(TARGET_PATH)
	# Run pre script
	if [ -n "$($*_PRE_SCRIPT)" ]; then :;$($*_PRE_SCRIPT) fi
	# Copy debian folder
	if [ -n "$($*_DEBIAN)" ]; then mkdir -p $($*_SRC_PATH)/debian; cp $($*_DEBIAN)/* -rf $($*_SRC_PATH)/debian/; fi
	# Apply series of patches if exist (exit loudly on real quilt failures; rc=2 means
	# "all patches already applied" which is harmless on a reused workspace)
	if [ -f $($*_SRC_PATH).patch/series ]; then \
	  pushd $($*_SRC_PATH); \
	  set +e; QUILT_PATCHES=../$(notdir $($*_SRC_PATH)).patch quilt push -a; QUILT_RC=$$?; set -e; \
	  if [ $$QUILT_RC -ne 0 ] && [ $$QUILT_RC -ne 2 ]; then echo "ERROR: quilt push -a failed (rc=$$QUILT_RC) for $($*_SRC_PATH).patch/series" >&2; exit $$QUILT_RC; fi; \
	  if [ -d .pc ]; then mv .pc .pc1; fi; popd; fi
	if [ -n "$($*_PATCH_EXT)" ]; then \
	  pushd $($*_SRC_PATH); \
	  set +e; QUILT_PATCHES=$($*_PATCH_EXT) quilt push -a; QUILT_RC=$$?; set -e; \
	  if [ $$QUILT_RC -ne 0 ] && [ $$QUILT_RC -ne 2 ]; then echo "ERROR: quilt push -a failed (rc=$$QUILT_RC) for $($*_PATCH_EXT)" >&2; exit $$QUILT_RC; fi; \
	  if [ -d .pc ]; then mv .pc .pc2; fi; popd; fi
	# Merge the debian patches if not applied
	if [ -f $($*_SRC_PATH).patch/debian.patch/series ]; then
	  LAST_PATCH=$$(tail -n1  $($*_SRC_PATH).patch/debian.patch/series)
	  if ! grep -q $$LAST_PATCH $($*_SRC_PATH)/debian/patches/series 2>/dev/null; then
	    echo "Applying patches for $($*_SRC_PATH)/debian/patches/"
	    cat $($*_SRC_PATH).patch/debian.patch/series >> $($*_SRC_PATH)/debian/patches/series
	    cp $($*_SRC_PATH).patch/debian.patch/*.patch $($*_SRC_PATH)/debian/patches/
	  fi
	fi
	if [ -n "$($*_MAKEFILE)" ]; then
	  $($*_BUILD_OPTIONS) make -C $($*_SRC_PATH) -f $($*_MAKEFILE) $(DEST)/$* | tee $(DEST)/$*.log
	elif [ -f $($*_SRC_PATH)/debian/control ]; then
	  pushd $($*_SRC_PATH)
	  VERSION=$$(dpkg-parsechangelog --show-field Version)
	  if [[ "$*" == *+fips_* ]] && [[ "$$VERSION" != *+fips ]]; then
	    sed -i "s/$$VERSION/$$VERSION+fips/" debian/changelog
	  fi
	  # Fix Misc/NEWS not found issue for python
	  if [[ "$*" == python3* ]]; then touch Misc/NEWS; fi
	  # Fix package overwrite issue, increase the timestamp
	  export SOURCE_DATE_EPOCH="$$(($$(dpkg-parsechangelog -STimestamp) + 86400))"
	  $($*_BUILD_OPTIONS) dpkg-buildpackage -b -d -rfakeroot -us -uc | tee $(DEST)/$*.log
	  popd
	  mkdir -p $(DEST)
	  mv -f $(addprefix $($*_SRC_PATH)/../, $* $($*_DERIVED_DEBS)) $(DEST)/
	else
	  error "Do not know how to make $(TARGET_PATH)/$*"
	fi
	if [ -n "$($*_PATCH_EXT)" ]; then pushd $($*_SRC_PATH) && rm -rf .pc && mv .pc2 .pc && quilt pop -a -f; [ -d .pc ] && rm -rf .pc; popd; fi || true
	if [ -f $($*_SRC_PATH).patch/series ]; then pushd $($*_SRC_PATH) && rm -rf .pc && mv .pc1 .pc && quilt pop -a -f; [ -d .pc ] && rm -rf .pc; popd; fi || true
