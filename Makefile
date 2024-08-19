
# Default is sh, which has scripting limitations
SHELL := $(shell command -v bash;)

##### Functions #####

# Evaluates to $(1) if $(1) non-empty, otherwise evaluates to $(2)
def_if_empty = $(if $(1),$(1),$(2))

# Dereference variable $(1), return value if non-empty, otherwise raise an error.
err_if_empty = $(if $(strip $($(1))),$(strip $($(1))),$(error Required variable $(1) is undefined or empty))

# Export variable $(1) to subsequent shell environments if contents are non-empty
export_full = $(eval export $(if $(call err_if_empty,$(1)),$(1)))

# Evaluate to the value of $(1) if $(CI) is the literal string "true", else $(2)
if_ci_else = $(if $(findstring true,$(CI)),$(1),$(2))

##### Important image release and source details #####

export CENTOS_STREAM_RELEASE = 9

# Warning: Beta Fedora releases are not supported.  Verifiy EC2 AMI availability
# here: https://fedoraproject.org/cloud/download
export FEDORA_RELEASE = 40
export PRIOR_FEDORA_RELEASE = 39

# This should always be one-greater than $FEDORA_RELEASE (assuming it's actually the latest)
export RAWHIDE_RELEASE = 41

# Automation assumes the actual release number (after SID upgrade)
# is always one-greater than the latest DEBIAN_BASE_FAMILY (GCE image).
export DEBIAN_RELEASE = 13
export DEBIAN_BASE_FAMILY = debian-12

IMPORT_FORMAT = vhdx

##### Important Paths and variables #####

# Lookup QCOW2 Image URLs and CHECKSUM files from
# https://dl.fedoraproject.org/pub/fedora/linux/
FEDORA_IMAGE_URL = $(shell ./get_fedora_url.sh image x86_64 $(FEDORA_RELEASE))
FEDORA_CSUM_URL = $(shell ./get_fedora_url.sh checksum x86_64 $(FEDORA_RELEASE))
FEDORA_ARM64_IMAGE_URL = $(shell ./get_fedora_url.sh image aarch64 $(FEDORA_RELEASE))
FEDORA_ARM64_CSUM_URL = $(shell ./get_fedora_url.sh checksum aarch64 $(FEDORA_RELEASE))
PRIOR_FEDORA_IMAGE_URL = $(shell ./get_fedora_url.sh image x86_64 $(PRIOR_FEDORA_RELEASE))
PRIOR_FEDORA_CSUM_URL = $(shell ./get_fedora_url.sh checksum x86_64 $(PRIOR_FEDORA_RELEASE))

# Most targets require possession of service-account credentials (JSON file)
# with sufficient access to the podman GCE project for creating VMs,
# VM images, and storage objects.
export GAC_FILEPATH

# When operating under Cirrus-CI, provide access to this for child processes
export CIRRUS_TASK_ID

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

# Suffix value for any images built from this make execution
_IMG_SFX ?= $(file <IMG_SFX)

# Env. vars needed by packer
export CHECKPOINT_DISABLE = 1  # Disable hashicorp phone-home
export PACKER_CACHE_DIR = $(call err_if_empty,_TEMPDIR)

# AWS CLI default, in case caller needs to override
export AWS := aws --output json --region us-east-1

# Needed for container-image builds
GIT_HEAD = $(shell git rev-parse HEAD)

# Save some typing
_IMGTS_FQIN := quay.io/libpod/imgts:c$(_IMG_SFX)

##### Targets #####

# N/B: The double-# after targets is gawk'd out as the target description
.PHONY: help
help: ## Default target, parses special in-line comments as documentation.
	@printf $(_HLPFMT) "Target:" "Description:"
	@printf $(_HLPFMT) "--------------" "--------------------"
	@grep -E '^[[:print:]]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":(.*)?## "}; {printf $(_HLPFMT), $$1, $$2}'

# N/B: This will become part of the GCE image name and AWS Image name-tag.
# There are length/character limitations (a-z, 0-9, -) in GCE for image
# names and a max-length of 63.
.PHONY: IMG_SFX
IMG_SFX:  timebomb-check ## Generate a new date-based image suffix, store in the file IMG_SFX
	$(file >$@,$(shell date --utc +%Y%m%dt%H%M%Sz)-f$(FEDORA_RELEASE)f$(PRIOR_FEDORA_RELEASE)d$(subst .,,$(DEBIAN_RELEASE)))
	@echo "$(file <IMG_SFX)"

# Prevent us from wasting CI time when we have expired timebombs
.PHONY: timebomb-check
timebomb-check:
	@now=$$(date --utc +%Y%m%d); \
	    found=; \
	    while read -r bomb; do \
	        when=$$(echo "$$bomb" | sed -e 's/^.*timebomb \([0-9]\+\).*/\1/'); \
	        if [ $$when -le $$now ]; then \
	            echo "$$bomb"; \
	            found=found; \
	        fi; \
	    done < <(git grep --line-number '^[ ]*timebomb '); \
	    if [[ -n "$$found" ]]; then \
	        echo ""; \
	        echo "****** FATAL: Please check/fix expired timebomb(s) ^^^^^^"; \
	        false; \
	    fi

# Given the path to a file containing 'sha256:<image id>' return <image id>
# or throw error if empty.
define imageid
	$(if $(file < $(1)),$(subst sha256:,,$(file < $(1))),$(error Container IID file $(1) doesn't exist or is empty))
endef

# This is intended for use by humans, to debug the image_builder_task in .cirrus.yml
# as well as the scripts under the ci subdirectory.  See the 'image_builder_debug`
# target if debugging of the packer builds is necessary.
.PHONY: ci_debug
ci_debug: $(_TEMPDIR)/ci_debug.iid ## Build and enter container for local development/debugging of container-based Cirrus-CI tasks
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
		$(call imageid,$<) $(if $(DBG_TEST_CMD),$(DBG_TEST_CMD),)

# Takes 3 arguments: IID filepath, FQIN, context dir
define podman_build
	podman build -t $(2) \
		--iidfile=$(1) \
		--build-arg CENTOS_STREAM_RELEASE=$(CENTOS_STREAM_RELEASE) \
		--build-arg PACKER_VERSION=$(call err_if_empty,PACKER_VERSION) \
		-f $(3)/Containerfile .
endef

$(_TEMPDIR)/ci_debug.iid: $(_TEMPDIR) $(wildcard ci/*)
	$(call podman_build,$@,ci_debug,ci)

$(_TEMPDIR):
	mkdir -p $@

$(_TEMPDIR)/bin: $(_TEMPDIR)
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

define build_podman_container
	$(MAKE) $(_TEMPDIR)/$(1).iid BASE_TAG=$(2)
endef

# First argument is the path to the template JSON
define packer_build
	env AWS_SHARED_CREDENTIALS_FILE="$(call err_if_empty,AWS_SHARED_CREDENTIALS_FILE)" \
		GAC_FILEPATH="$(call err_if_empty,GAC_FILEPATH)" \
		FEDORA_IMAGE_URL=$(call err_if_empty,FEDORA_IMAGE_URL) \
		FEDORA_CSUM_URL=$(call err_if_empty,FEDORA_CSUM_URL) \
		FEDORA_ARM64_IMAGE_URL=$(call err_if_empty,FEDORA_ARM64_IMAGE_URL) \
		FEDORA_ARM64_CSUM_URL=$(call err_if_empty,FEDORA_ARM64_CSUM_URL) \
		PRIOR_FEDORA_IMAGE_URL=$(call err_if_empty,PRIOR_FEDORA_IMAGE_URL) \
		PRIOR_FEDORA_CSUM_URL=$(call err_if_empty,PRIOR_FEDORA_CSUM_URL) \
			$(PACKER_INSTALL_DIR)/packer build \
			-force \
			-var TEMPDIR="$(_TEMPDIR)" \
			-var IMG_SFX="$(call err_if_empty,_IMG_SFX)" \
			$(if $(PACKER_BUILDS),-only=$(PACKER_BUILDS)) \
			$(if $(DEBUG_NESTED_VM),-var TTYDEV=$(shell tty),-var TTYDEV=/dev/null) \
			$(if $(PACKER_BUILD_ARGS),$(PACKER_BUILD_ARGS)) \
			$(1)
endef

.PHONY: image_builder
image_builder: image_builder/manifest.json ## Create image-building image and import into GCE (needed for making all other images)
image_builder/manifest.json: image_builder/gce.json image_builder/setup.sh lib.sh systemd_banish.sh $(PACKER_INSTALL_DIR)/packer
	$(call packer_build,image_builder/gce.json)

# Note: It's assumed there are important files in the callers $HOME
# needed for debugging (.gitconfig, .ssh keys, etc.).  It's unsafe
# to assume $(_MKFILE_DIR) is also under $HOME.  Both are mounted
# for good measure.
.PHONY: image_builder_debug
image_builder_debug: $(_TEMPDIR)/image_builder_debug.iid ## Build and enter container for local development/debugging of targets requiring packer + virtualization
	/usr/bin/podman run -it --rm \
		--security-opt label=disable \
		-v $$HOME:$$HOME \
		-v $(_MKFILE_DIR):$(_MKFILE_DIR) \
		-w $(_MKFILE_DIR) \
		-v $(_TEMPDIR):$(_TEMPDIR) \
		-v $(call err_if_empty,GAC_FILEPATH):$(GAC_FILEPATH) \
		-v $(call err_if_empty,AWS_SHARED_CREDENTIALS_FILE):$(AWS_SHARED_CREDENTIALS_FILE) \
		-v /dev/kvm:/dev/kvm \
		-e PACKER_INSTALL_DIR=/usr/local/bin \
		-e PACKER_VERSION=$(call err_if_empty,PACKER_VERSION) \
		-e IMG_SFX=$(call err_if_empty,_IMG_SFX) \
		-e GAC_FILEPATH=$(GAC_FILEPATH) \
		-e AWS_SHARED_CREDENTIALS_FILE=$(AWS_SHARED_CREDENTIALS_FILE) \
		$(call imageid,$<) $(if $(DBG_TEST_CMD),$(DBG_TEST_CMD))

$(_TEMPDIR)/image_builder_debug.iid: $(_TEMPDIR) $(wildcard image_builder/*)
	$(call podman_build,$@,image_builder_debug,image_builder)

.PHONY: base_images
# This needs to run in a virt/nested-virt capable environment
base_images: base_images/manifest.json ## Create, prepare, and import base-level images into GCE.

base_images/manifest.json: base_images/cloud.json $(wildcard base_images/*.sh) cidata $(_TEMPDIR)/cidata.ssh $(PACKER_INSTALL_DIR)/packer
	$(call packer_build,base_images/cloud.json)

.PHONY: cache_images
cache_images: cache_images/manifest.json ## Create, prepare, and import top-level images into GCE.
cache_images/manifest.json: cache_images/cloud.json $(wildcard cache_images/*.sh) $(PACKER_INSTALL_DIR)/packer
	$(call packer_build,cache_images/cloud.json)

.PHONY: win_images
# This needs to run in a virt/nested-virt capable environment
win_images: win_images/manifest.json
win_images/manifest.json: win_images/win-server-wsl.json $(wildcard win_images/*.ps1) $(PACKER_INSTALL_DIR)/packer
	$(call packer_build,win_images/win-server-wsl.json)

.PHONY: fedora_podman
fedora_podman:  ## Build Fedora podman development container
	$(call build_podman_container,$@,$(FEDORA_RELEASE))

.PHONY: prior-fedora_podman
prior-fedora_podman:  ## Build Prior-Fedora podman development container
	$(call build_podman_container,$@,$(PRIOR_FEDORA_RELEASE))

$(_TEMPDIR)/%_podman.iid: podman/Containerfile podman/setup.sh $(wildcard base_images/*.sh) $(_TEMPDIR) $(wildcard cache_images/*.sh)
	podman build -t $*_podman:$(call err_if_empty,_IMG_SFX) \
		--security-opt seccomp=unconfined \
		--iidfile=$@ \
		--build-arg=BASE_NAME=$(subst prior-,,$*) \
		--build-arg=BASE_TAG=$(call err_if_empty,BASE_TAG) \
		--build-arg=PACKER_BUILD_NAME=$(subst _podman,,$*) \
		--build-arg=IMG_SFX=$(_IMG_SFX) \
		--build-arg=CIRRUS_TASK_ID=$(CIRRUS_TASK_ID) \
		--build-arg=GIT_HEAD=$(call err_if_empty,GIT_HEAD) \
		-f podman/Containerfile .

.PHONY: skopeo_cidev
skopeo_cidev: $(_TEMPDIR)/skopeo_cidev.iid  ## Build Skopeo development and CI container
$(_TEMPDIR)/skopeo_cidev.iid: $(_TEMPDIR) $(wildcard skopeo_base/*)
	podman build -t skopeo_cidev:$(call err_if_empty,_IMG_SFX) \
		--iidfile=$@ \
		--security-opt seccomp=unconfined \
		--build-arg=BASE_TAG=$(FEDORA_RELEASE) \
		skopeo_cidev

.PHONY: ccia
ccia: $(_TEMPDIR)/ccia.iid  ## Build the Cirrus-CI Artifacts container image
$(_TEMPDIR)/ccia.iid: ccia/Containerfile $(_TEMPDIR)
	$(call podman_build,$@,ccia:$(call err_if_empty,_IMG_SFX),ccia)

# Note: This target only builds imgts:c$(_IMG_SFX) it does not push it to
# any container registry which may be required for targets which
# depend on it as a base-image.  In CI, pushing is handled automatically
# by the 'ci/make_container_images.sh' script.
.PHONY: imgts
imgts: imgts/Containerfile imgts/entrypoint.sh imgts/google-cloud-sdk.repo imgts/lib_entrypoint.sh $(_TEMPDIR)  ## Build the VM image time-stamping container image
	$(call podman_build,/dev/null,imgts:$(call err_if_empty,_IMG_SFX),imgts)
	-rm $(_TEMPDIR)/$@.iid

# Helper function to build images which depend on imgts:latest base image
# N/B: There is no make dependency resolution on imgts.iid on purpose,
# imgts:c$(_IMG_SFX) is assumed to have already been pushed to quay.
# See imgts target above.
define imgts_base_podman_build
	podman image exists $(_IMGTS_FQIN) || podman pull $(_IMGTS_FQIN)
	podman image exists imgts:latest || podman tag $(_IMGTS_FQIN) imgts:latest
	$(call podman_build,$@,$(1):$(call err_if_empty,_IMG_SFX),$(1))
endef

.PHONY: imgobsolete
imgobsolete: $(_TEMPDIR)/imgobsolete.iid  ## Build the VM Image obsoleting container image
$(_TEMPDIR)/imgobsolete.iid: imgts/lib_entrypoint.sh imgobsolete/Containerfile imgobsolete/entrypoint.sh $(_TEMPDIR)
	$(call imgts_base_podman_build,imgobsolete)

.PHONY: imgprune
imgprune: $(_TEMPDIR)/imgprune.iid  ## Build the VM Image pruning container image
$(_TEMPDIR)/imgprune.iid: imgts/lib_entrypoint.sh imgprune/Containerfile imgprune/entrypoint.sh $(_TEMPDIR)
	$(call imgts_base_podman_build,imgprune)

.PHONY: gcsupld
gcsupld: $(_TEMPDIR)/gcsupld.iid  ## Build the GCS Upload container image
$(_TEMPDIR)/gcsupld.iid: imgts/lib_entrypoint.sh gcsupld/Containerfile gcsupld/entrypoint.sh $(_TEMPDIR)
	$(call imgts_base_podman_build,gcsupld)

.PHONY: orphanvms
orphanvms: $(_TEMPDIR)/orphanvms.iid  ## Build the Orphaned VM container image
$(_TEMPDIR)/orphanvms.iid: imgts/lib_entrypoint.sh orphanvms/Containerfile orphanvms/entrypoint.sh orphanvms/_gce orphanvms/_ec2 $(_TEMPDIR)
	$(call imgts_base_podman_build,orphanvms)

.PHONY: .get_ci_vm
get_ci_vm: $(_TEMPDIR)/get_ci_vm.iid  ## Build the get_ci_vm container image
$(_TEMPDIR)/get_ci_vm.iid: lib.sh get_ci_vm/Containerfile get_ci_vm/entrypoint.sh get_ci_vm/setup.sh $(_TEMPDIR)
	podman build --iidfile=$@ -t get_ci_vm:$(call err_if_empty,_IMG_SFX) -f get_ci_vm/Containerfile ./

.PHONY: clean
clean: ## Remove all generated files referenced in this Makefile
	-rm -rf $(_TEMPDIR)
	-rm -f image_builder/*.json
	-rm -f *_images/{*.json,cidata*,*-data}
	-podman rmi imgts:latest
	-podman rmi $(_IMGTS_FQIN)
