
##### Functions #####

# Evaluates to $(1) if $(1) non-empty, otherwise evaluates to $(2)
def_if_empty = $(if $(1),$(1),$(2))

# Dereference variable $(1), return value if non-empty, otherwise raise an error.
err_if_empty = $(if $(strip $($(1))),$(strip $($(1))),$(error Required variable $(1) is undefined or empty))

# Export variable $(1) to subsequent shell environments if contents are non-empty
export_full = $(eval export $(if $(call err_if_empty,$(1)),$(1)))

# Evaluate to the value of $(1) if $(CI) is the literal string "true", else $(2)
if_ci_else = $(if $(findstring true,$(CI)),$(1),$(2))

##### Important Paths and variables #####

# Most targets require possession of service-account credentials (JSON file)
# with sufficient access to the podman GCE project for creating VMs,
# VM images, and storage objects.
export GAC_FILEPATH

PACKER_LOG ?=
# Uncomment tthe following to enable additional logging from packer.
#PACKER_LOG = 1
export PACKER_LOG

DEBUG_NESTED_VM ?=
# Base-images must be created in a nested VM, inside a GCE VM.
# This presents some unique debugging challenges.  Uncomment the following
# to make packer display raw nested-VM console output.  N/B: This will
# FUBAR the regular packer output by mangling CR/LF. Only enable if absolutely
# necessary, try PACKER_LOG=1 (above) first.
#override DEBUG_NESTED_VM := 1
export DEBUG_NESTED_VM

# Set to CSV of builder-names from YAML, or empty for "all"
PACKER_BUILDS ?=
# Needed for locating certain files/scripts (n/b: trailing-slash included)
override _MKFILE_PATH := $(lastword $(MAKEFILE_LIST))
override _MKFILE_DIR := $(abspath $(dir $(_MKFILE_PATH)))

# Large files will be stored in $TEMPDIR, set it beforehand if necessary.
# Expected to be a directory which can be created, written to, and removed.
# (n/b: trailing-slash included to prevent 'clean' target accidents)
override _TEMPDIR ?= $(abspath $(if $(TEMPDIR),$(TEMPDIR),/tmp/$(notdir $(_MKFILE_DIR))_tmp))

# Packer binary expected to be here | location for 'install_packer' to use
PACKER_INSTALL_DIR ?= $(_TEMPDIR)/
# Default base path to directory containing packer template files
PKR_DIR ?= $(_MKFILE_DIR)/packer
override _PKR_DIR := $(abspath $(call err_if_empty,PKR_DIR))

OSTYPE ?= linux
OSARCH ?= amd64
# Next version (1.5) changes DSL: JSON -> HCL
PACKER_VERSION ?= 1.4.5
override _PACKER_URL := https://releases.hashicorp.com/packer/$(PACKER_VERSION)/packer_$(PACKER_VERSION)_$(OSTYPE)_$(OSARCH).zip

# Align each line properly to the header
override _HLPFMT = "%-20s %s\n"

# Suffix used to identify images produce by _this_ execution
# N/B: There are length/character limitations in GCE for image names
IMG_SFX ?=

##### Targets #####

# N/B: The double-# after targets is gawk'd out as the target description
.PHONY: help
help: ## Default target, parses special in-line comments as documentation.
	@printf $(_HLPFMT) "Target:" "Description:"
	@printf $(_HLPFMT) "--------------" "--------------------"
	@grep -E '^[a-zA-Z0-9_\-\]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":(.*)?## "}; {printf $(_HLPFMT), $$1, $$2}'

.PHONY: ci_debug
ci_debug: $(_TEMPDIR)/ci_debug.tar ## Build and enter container for local development/debugging of container-based Cirrus-CI tasks
	$(eval override _GAC_FILEPATH := $(call err_if_empty,GAC_FILEPATH))
	/usr/bin/podman run -it --rm \
		--security-opt label=disable -v $$PWD:$$PWD -w $$PWD \
		-v $(_TEMPDIR):$(_TEMPDIR):Z -v $(_GAC_FILEPATH):$(_GAC_FILEPATH):Z \
		-e PACKER_INSTALL_DIR=/usr/local/bin \
		-e GAC_FILEPATH=$(GAC_FILEPATH) -e TEMPDIR=$(_TEMPDIR) \
		docker-archive:$<

define podman_build
	podman build -t $(2) -v $(_TEMPDIR)/var_cache_dnf:/var/cache/dnf:Z -f $(3)/Containerfile .
	rm -f $(1)
	podman save --quiet -o $(1) $(2)
	podman rmi $(2)
endef

$(_TEMPDIR)/ci_debug.tar: $(_TEMPDIR)/var_cache_dnf ci/Containerfile ci/install_packages.txt ci/install_packages.sh lib.sh
	$(call podman_build,$@,ci_debug,ci)

$(_TEMPDIR):
	mkdir -p $@

$(_TEMPDIR)/bin: $(_TEMPDIR)
	mkdir -p $@

$(_TEMPDIR)/var_cache_dnf: $(_TEMPDIR)
	mkdir -p $@

$(_TEMPDIR)/packer.zip: $(_TEMPDIR)
	curl -L --silent --show-error "$(_PACKER_URL)" -o "$@"

$(PACKER_INSTALL_DIR)/packer:
	make $(_TEMPDIR)/packer.zip TEMPDIR=$(_TEMPDIR)
	mkdir -p $(PACKER_INSTALL_DIR)
	cd $(PACKER_INSTALL_DIR) && unzip -o "$(_TEMPDIR)/packer.zip"
	touch $(PACKER_INSTALL_DIR)/packer
	$(PACKER_INSTALL_DIR)/packer --version

.PHONY: install_packer
install_packer: $(PACKER_INSTALL_DIR)/packer  ## Download and install packer in $PACKER_INSTALL_DIR

%.json: %.yml
	python3 -c 'import json,yaml; json.dump( yaml.safe_load(open("$<").read()), open("$@","w"), indent=2);'

$(_TEMPDIR)/cidata.ssh: $(_TEMPDIR)
	-rm -f "$@"
	ssh-keygen -f $@ -P "" -q

$(_TEMPDIR)/cidata.ssh.pub: $(_TEMPDIR) $(_TEMPDIR)/cidata.ssh
	touch $@

$(_TEMPDIR)/meta-data: $(_TEMPDIR)
	echo "local-hostname: localhost.localdomain" > $@

$(_TEMPDIR)/user-data: $(_TEMPDIR) $(_TEMPDIR)/cidata.ssh.pub
	cd $(_TEMPDIR) && \
		bash $(_MKFILE_DIR)/make-user-data.sh

$(_TEMPDIR)/cidata.iso: $(_TEMPDIR) $(_TEMPDIR)/user-data $(_TEMPDIR)/meta-data
	cd $(_TEMPDIR) && \
	genisoimage -output ./cidata.iso -volid cidata -input-charset utf-8 \
		-joliet -rock ./user-data ./meta-data

define packer_build
	env PACKER_CACHE_DIR="$(_TEMPDIR)" \
		CHECKPOINT_DISABLE=1 \
			$(PACKER_INSTALL_DIR)/packer build \
			-force \
			-var TEMPDIR="$(_TEMPDIR)" \
			-var GAC_FILEPATH="$(_GAC_FILEPATH)" \
			$(if $(PACKER_BUILDS),-only=$(PACKER_BUILDS)) \
			$(if $(IMG_SFX),-var IMG_SFX=$(IMG_SFX)) \
			$(if $(DEBUG_NESTED_VM),-var TTYDEV=$(shell tty),-var TTYDEV=/dev/null) \
			$(1)
endef

image_builder: image_builder/manifest.json
image_builder/manifest.json: image_builder/gce.json image_builder/setup.sh lib.sh systemd_banish.sh $(PACKER_INSTALL_DIR)/packer ## Create image-building image and import into GCE (needed for making 'base_images'
	$(eval override _GAC_FILEPATH := $(call err_if_empty,GAC_FILEPATH))
	$(call packer_build,$<)

# Note: We assume this repo is checked out somewhere under the caller's
# home-dir for bind-mounting purposes.  Otherwise possibly necessary
# files/directories like $HOME/.gitconfig or $HOME/.ssh/ won't be available
# from inside the debugging container.
.PHONY: image_builder_debug
image_builder_debug: $(_TEMPDIR)/image_builder_debug.tar ## Build and enter container for local development/debugging of targets requiring packer + virtualization
	$(eval override _GAC_FILEPATH := $(call err_if_empty,GAC_FILEPATH))
	/usr/bin/podman run -it --rm \
		--security-opt label=disable -v $$HOME:$$HOME -w $$PWD \
		-v $(_TEMPDIR):$(_TEMPDIR):Z -v $(_GAC_FILEPATH):$(_GAC_FILEPATH):Z \
		-v /dev/kvm:/dev/kvm \
		-e PACKER_INSTALL_DIR=/usr/local/bin \
		-e GAC_FILEPATH=$(GAC_FILEPATH) -e TEMPDIR=$(_TEMPDIR) \
		docker-archive:$<

$(_TEMPDIR)/image_builder_debug.tar: $(_TEMPDIR) $(_TEMPDIR)/var_cache_dnf image_builder/Containerfile image_builder/install_packages.txt ci/install_packages.sh lib.sh
	$(call podman_build,$@,image_builder_debug,image_builder)

# This needs to run in a virt/nested-virt capible environment
base_images: base_images/manifest.json
base_images/manifest.json: base_images/gce.json base_images/fedora_base-setup.sh $(_TEMPDIR)/cidata.iso $(_TEMPDIR)/cidata.ssh $(PACKER_INSTALL_DIR)/packer  ## Create, prepare, and import base-level images into GCE.  Optionally, set PACKER_BUILDS=<csv> to select builder(s).
	$(eval override _GAC_FILEPATH := $(call err_if_empty,GAC_FILEPATH))
	$(call packer_build,$<)

cache_images: cache_images/manifest.json
cache_images/manifest.json: cache_images/gce.json $(wildcard cache_images/*.sh) $(PACKER_INSTALL_DIR)/packer  ## Create, prepare, and import top-level images into GCE.  Optionally, set PACKER_BUILDS=<csv> to select builder(s).
	$(eval override _GAC_FILEPATH := $(call err_if_empty,GAC_FILEPATH))
	$(call packer_build,$<)

.PHONY: clean
clean: ## Remove all generated files referenced in this Makefile
	-rm -vrf $(_TEMPDIR)
	-rm -f image_builder/*.json
	-rm -f base_images/{*.json,cidata*,*-data}
	-rm -f ci_debug.tar
