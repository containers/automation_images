
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

# Ditto for AWS credentials (INI file) with access to create VMs and images.
# ref: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html#cli-configure-files-where
export AWS_SHARED_CREDENTIALS_FILE

PACKER_LOG ?=
# Uncomment the following to enable additional logging from packer.
#override PACKER_LOG := 1
export PACKER_LOG

DEBUG_NESTED_VM ?=
# Base-images must be created in a nested VM, inside a GCE VM.
# This presents some unique debugging challenges.  Uncomment the following
# to make packer display raw nested-VM console output.  N/B: This will
# FUBAR the regular packer output by mangling CR/LF. Only enable if absolutely
# necessary, try PACKER_LOG=1 (above) first.
#override DEBUG_NESTED_VM := 1
export DEBUG_NESTED_VM

# Sometimes additional arguments need to be specified on the make command-line.
# For example, setting `-on-error=ask` or `-var some=thing`
PACKER_BUILD_ARGS ?=

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
PACKER_VERSION ?= $(shell bash ./get_packer_version.sh)
override _PACKER_URL := https://releases.hashicorp.com/packer/$(strip $(call err_if_empty,PACKER_VERSION))/packer_$(strip $(PACKER_VERSION))_$(OSTYPE)_$(OSARCH).zip

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
	@grep -E '^[[:print:]]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":(.*)?## "}; {printf $(_HLPFMT), $$1, $$2}'

.PHONY: ci_debug
ci_debug: $(_TEMPDIR)/ci_debug.tar ## Build and enter container for local development/debugging of container-based Cirrus-CI tasks
	/usr/bin/podman run -it --rm \
		--security-opt label=disable \
		-v $(_MKFILE_DIR):$(_MKFILE_DIR) -w $(_MKFILE_DIR) \
		-v $(_TEMPDIR):$(_TEMPDIR) \
		-v $(call err_if_empty,GAC_FILEPATH):$(GAC_FILEPATH) \
		-v $(call err_if_empty,AWS_SHARED_CREDENTIALS_FILE):$(AWS_SHARED_CREDENTIALS_FILE) \
		-e PACKER_INSTALL_DIR=/usr/local/bin \
		-e PACKER_VERSION=$(call err_if_empty,PACKER_VERSION) \
		-e GAC_FILEPATH=$(GAC_FILEPATH) \
		-e AWS_SHARED_CREDENTIALS_FILE=$(AWS_SHARED_CREDENTIALS_FILE) \
		-e TEMPDIR=$(_TEMPDIR) \
		docker-archive:$<

# Takes 4 arguments: export filepath, FQIN, context dir, package cache key
define podman_build
	podman build -t $(2) \
		--security-opt seccomp=unconfined \
		-v $(_TEMPDIR)/.cache/$(4):/var/cache/dnf:Z \
		-v $(_TEMPDIR)/.cache/$(4):/var/cache/apt:Z \
		--build-arg PACKER_VERSION=$(call err_if_empty,PACKER_VERSION) \
		-f $(3)/Containerfile .
	rm -f $(1)
	podman save --quiet -o $(1) $(2)
endef

$(_TEMPDIR)/ci_debug.tar: $(_TEMPDIR)/.cache/fedora $(wildcard ci/*)
	$(call podman_build,$@,ci_debug,ci,fedora)

$(_TEMPDIR):
	mkdir -p $@

$(_TEMPDIR)/bin: $(_TEMPDIR)
	mkdir -p $@

$(_TEMPDIR)/.cache: $(_TEMPDIR)
	mkdir -p $@

$(_TEMPDIR)/.cache/%: $(_TEMPDIR)/.cache
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
	python3 -c 'import json,yaml; json.dump( yaml.safe_load(open("$<").read()), open("$@","w"), indent=2 );'

$(_TEMPDIR)/cidata.ssh: $(_TEMPDIR)
	-rm -f "$@"
	ssh-keygen -f $@ -P "" -q -t ed25519

$(_TEMPDIR)/cidata.ssh.pub: $(_TEMPDIR) $(_TEMPDIR)/cidata.ssh
	touch $@

$(_TEMPDIR)/meta-data: $(_TEMPDIR)
	echo "local-hostname: localhost.localdomain" > $@

$(_TEMPDIR)/user-data: $(_TEMPDIR) $(_TEMPDIR)/cidata.ssh.pub $(_TEMPDIR)/cidata.ssh
	cd $(_TEMPDIR) && \
		bash $(_MKFILE_DIR)/make-user-data.sh

.PHONY: cidata
cidata: $(_TEMPDIR)/user-data $(_TEMPDIR)/meta-data

# First argument is the path to the template JSON, second
# argument is the path to AWS_SHARED_CREDENTIALS_FILE
# when required.  N/B: GAC_FILEPATH is always required.
define packer_build
	env PACKER_CACHE_DIR="$(_TEMPDIR)" \
		AWS_SHARED_CREDENTIALS_FILE="$(2)" \
		GAC_FILEPATH="$(call err_if_empty,GAC_FILEPATH)" \
		CHECKPOINT_DISABLE=1 \
			$(PACKER_INSTALL_DIR)/packer build \
			-force \
			-var TEMPDIR="$(_TEMPDIR)" \
			$(if $(PACKER_BUILDS),-only=$(PACKER_BUILDS)) \
			$(if $(IMG_SFX),-var IMG_SFX=$(IMG_SFX)) \
			$(if $(DEBUG_NESTED_VM),-var TTYDEV=$(shell tty),-var TTYDEV=/dev/null) \
			$(if $(PACKER_BUILD_ARGS),$(PACKER_BUILD_ARGS)) \
			$(1)
endef

.PHONY: image_builder
image_builder: image_builder/manifest.json ## Create image-building image and import into GCE (needed for making all other images)
image_builder/manifest.json: image_builder/gce.json image_builder/setup.sh lib.sh systemd_banish.sh $(PACKER_INSTALL_DIR)/packer
	$(call packer_build,$<,)

# Note: We assume this repo is checked out somewhere under the caller's
# home-dir for bind-mounting purposes.  Otherwise possibly necessary
# files/directories like $HOME/.gitconfig or $HOME/.ssh/ won't be available
# from inside the debugging container.
.PHONY: image_builder_debug
image_builder_debug: $(_TEMPDIR)/image_builder_debug.tar ## Build and enter container for local development/debugging of targets requiring packer + virtualization
	/usr/bin/podman run -it --rm \
		--security-opt label=disable -v $$HOME:$$HOME -w $(_MKFILE_DIR) \
		-v $(_TEMPDIR):$(_TEMPDIR) \
		-v $(call err_if_empty,GAC_FILEPATH):$(GAC_FILEPATH) \
		-v $(call err_if_empty,AWS_SHARED_CREDENTIALS_FILE):$(AWS_SHARED_CREDENTIALS_FILE) \
		-v /dev/kvm:/dev/kvm \
		-e PACKER_INSTALL_DIR=/usr/local/bin \
		-e PACKER_VERSION=$(call err_if_empty,PACKER_VERSION) \
		-e IMG_SFX=$(call err_if_empty,IMG_SFX) \
		-e GAC_FILEPATH=$(GAC_FILEPATH) \
		-e AWS_SHARED_CREDENTIALS_FILE=$(AWS_SHARED_CREDENTIALS_FILE) \
		docker-archive:$<

$(_TEMPDIR)/image_builder_debug.tar: $(_TEMPDIR)/.cache/centos $(wildcard image_builder/*)
	$(call podman_build,$@,image_builder_debug,image_builder,centos)

.PHONY: base_images
# This needs to run in a virt/nested-virt capable environment
base_images: base_images/manifest.json ## Create, prepare, and import base-level images into GCE.  Optionally, set PACKER_BUILDS=<csv> to select builder(s).

base_images/manifest.json: base_images/cloud.json $(wildcard base_images/*.sh) cidata $(_TEMPDIR)/cidata.ssh $(PACKER_INSTALL_DIR)/packer
	$(call packer_build,base_images/cloud.json,$(call err_if_empty,AWS_SHARED_CREDENTIALS_FILE))

.PHONY: cache_images
cache_images: cache_images/manifest.json ## Create, prepare, and import top-level images into GCE.  Optionally, set PACKER_BUILDS=<csv> to select builder(s).
cache_images/manifest.json: cache_images/cloud.json $(wildcard cache_images/*.sh) $(PACKER_INSTALL_DIR)/packer
	$(call packer_build,cache_images/cloud.json,$(call err_if_empty,AWS_SHARED_CREDENTIALS_FILE))

override _fedora_podman_release := $(file < podman/fedora_release)
override _prior-fedora_podman_release := $(file < podman/prior-fedora_release)
override _ubuntu_podman_release := $(file < podman/ubuntu_release)
define build_podman_container
	$(MAKE) $(_TEMPDIR)/$(1).tar BASE_TAG=$(_$(1)_release)
endef

.PHONY: fedora_podman
fedora_podman:  ## Build Fedora podman development container
	$(call build_podman_container,$@,fedora)

.PHONY: prior-fedora_podman
prior-fedora_podman:  ## Build Prior-Fedora podman development container
	$(call build_podman_container,$@,prior-fedora)

.PHONY: ubuntu_podman
ubuntu_podman:  ## Build Ubuntu podman development container
	$(call build_podman_container,$@,ubuntu)

$(_TEMPDIR)/%_podman.tar: podman/Containerfile podman/setup.sh $(wildcard base_images/*.sh) $(wildcard cache_images/*.sh) $(_TEMPDIR)/.cache/%
	podman build -t $*_podman:$(call err_if_empty,IMG_SFX) \
		--security-opt seccomp=unconfined \
		--build-arg=BASE_NAME=$(subst prior-,,$*) \
		--build-arg=BASE_TAG=$(call err_if_empty,BASE_TAG) \
		--build-arg=PACKER_BUILD_NAME=$(subst _podman,,$*) \
		--platform linux/amd64,linux/arm64 \
		-v $(_TEMPDIR)/.cache/$*:/var/cache/dnf:Z \
		-v $(_TEMPDIR)/.cache/$*:/var/cache/apt:Z \
		-f podman/Containerfile .
	rm -f $@
	podman save --quiet -o $@ $*_podman:$(IMG_SFX)

.PHONY: skopeo_cidev
skopeo_cidev: $(_TEMPDIR)/skopeo_cidev.tar  ## Build Skopeo development and CI container
$(_TEMPDIR)/skopeo_cidev.tar: podman/fedora_release $(wildcard skopeo_base/*) $(_TEMPDIR)/.cache/fedora
	podman build -t skopeo_cidev:$(call err_if_empty,IMG_SFX) \
		--security-opt seccomp=unconfined \
		--build-arg=BASE_TAG=$(_fedora_podman_release) \
		-v $(_TEMPDIR)/.cache/fedora:/var/cache/dnf:Z \
		skopeo_cidev
	rm -f $@
	podman save --quiet -o $@ skopeo_cidev:$(IMG_SFX)

.PHONY: ccia
ccia: $(_TEMPDIR)/ccia.tar  ## Build the Cirrus-CI Artifacts container image
$(_TEMPDIR)/ccia.tar: ccia/Containerfile
	podman build -t ccia:$(call err_if_empty,IMG_SFX) \
		--security-opt seccomp=unconfined \
		--build-arg=BASE_TAG=$(_fedora_podman_release) \
		ccia
	rm -f $@
	podman save --quiet -o $@ ccia:$(IMG_SFX)

.PHONY: imgts
imgts: $(_TEMPDIR)/imgts.tar  ## Build the VM image time-stamping container image
$(_TEMPDIR)/imgts.tar: imgts/Containerfile imgts/entrypoint.sh imgts/google-cloud-sdk.repo imgts/lib_entrypoint.sh $(_TEMPDIR)/.cache/centos
	$(call podman_build,$@,imgts:$(call err_if_empty,IMG_SFX),imgts,centos)

define imgts_base_podman_build
	podman load -i $(_TEMPDIR)/imgts.tar
	podman tag imgts:$(call err_if_empty,IMG_SFX) imgts:latest
	$(call podman_build,$@,$(1):$(call err_if_empty,IMG_SFX),$(1),centos)
endef

.PHONY: imgobsolete
imgobsolete: $(_TEMPDIR)/imgobsolete.tar  ## Build the VM Image obsoleting container image
$(_TEMPDIR)/imgobsolete.tar: $(_TEMPDIR)/imgts.tar imgts/lib_entrypoint.sh imgobsolete/Containerfile imgobsolete/entrypoint.sh $(_TEMPDIR)/.cache/centos
	$(call imgts_base_podman_build,imgobsolete)

.PHONY: imgprune
imgprune: $(_TEMPDIR)/imgprune.tar  ## Build the VM Image pruning container image
$(_TEMPDIR)/imgprune.tar: $(_TEMPDIR)/imgts.tar imgts/lib_entrypoint.sh imgprune/Containerfile imgprune/entrypoint.sh $(_TEMPDIR)/.cache/centos
	$(call imgts_base_podman_build,imgprune)

.PHONY: gcsupld
gcsupld: $(_TEMPDIR)/gcsupld.tar  ## Build the GCS Upload container image
$(_TEMPDIR)/gcsupld.tar: $(_TEMPDIR)/imgts.tar imgts/lib_entrypoint.sh gcsupld/Containerfile gcsupld/entrypoint.sh $(_TEMPDIR)/.cache/centos
	$(call imgts_base_podman_build,gcsupld)

.PHONY: orphanvms
orphanvms: $(_TEMPDIR)/orphanvms.tar  ## Build the Orphaned VM container image
$(_TEMPDIR)/orphanvms.tar: $(_TEMPDIR)/imgts.tar imgts/lib_entrypoint.sh orphanvms/Containerfile orphanvms/entrypoint.sh $(_TEMPDIR)/.cache/centos
	$(call imgts_base_podman_build,orphanvms)

.PHONY: .get_ci_vm
get_ci_vm: $(_TEMPDIR)/get_ci_vm.tar  ## Build the get_ci_vm container image
$(_TEMPDIR)/get_ci_vm.tar: lib.sh get_ci_vm/Containerfile get_ci_vm/entrypoint.sh get_ci_vm/setup.sh $(_TEMPDIR)
	podman build -t get_ci_vm:$(call err_if_empty,IMG_SFX) -f get_ci_vm/Containerfile .
	rm -f $@
	podman save --quiet -o $@ get_ci_vm:$(IMG_SFX)

.PHONY: clean
clean: ## Remove all generated files referenced in this Makefile
	-rm -rf $(_TEMPDIR)
	-rm -f image_builder/*.json
	-rm -f base_images/{*.json,cidata*,*-data}
	-rm -f ci_debug.tar
