SHELL := bash

ROOT_DIR := $(shell git rev-parse --show-toplevel)
BUILD_DIR ?= $(ROOT_DIR)/build
OUTPUT_DIR ?= $(ROOT_DIR)/output
DIRS = $(BUILD_DIR) $(OUTPUT_DIR)
export PACKER_CACHE_DIR ?= $(BUILD_DIR)/packer_cache

NAME ?= openwrt
VERSION ?= 22.03.2
TIMESTAMP := $(shell date +%s)
BOX_NAME ?= $(NAME)-$(VERSION)
VM_NAME ?= $(NAME)-$(VERSION)

VER_MAJOR := $(shell echo $(VERSION) | cut -f1 -d.)
VER_MINOR := $(shell echo $(VERSION) | cut -f2 -d.)
VER_LT_21 := $(shell [ $(VER_MAJOR) -lt 21 ] && echo true)

REMOTE_FILE := openwrt-$(VERSION)-x86-64-generic-ext4-combined.img.gz
ifeq ($(VER_LT_21),true)
	REMOTE_FILE := openwrt-$(VERSION)-x86-64-combined-ext4.img.gz
endif

## Create build dirs
.PHONY: dirs
dirs: $(DIRS)

$(filter %,$(DIRS)):
	echo "create dirs"
	mkdir -p "$@"

.PHONY: get
get: $(BUILD_DIR)/openwrt-$(VERSION).img ## Download image

$(BUILD_DIR)/openwrt-$(VERSION).img:
	mkdir -p $(@D)
	if [ ! -f "$(BUILD_DIR)/openwrt-$(VERSION).img" ]; then \
		wget -O "$(BUILD_DIR)/openwrt-$(VERSION).img.gz" "https://downloads.openwrt.org/releases/$(VERSION)/targets/x86/64/$(REMOTE_FILE)"; \
  		gzip -f -d "$(BUILD_DIR)/openwrt-$(VERSION).img.gz" || exit 0; \
  		touch -m "$(BUILD_DIR)/openwrt-$(VERSION).img"; \
	fi

.PHONY: vdi
vdi: $(BUILD_DIR)/openwrt-$(VERSION).vdi ## Convert RAW disk image to VDI format

$(BUILD_DIR)/openwrt-$(VERSION).vdi: $(BUILD_DIR)/openwrt-$(VERSION).img
	VBoxManage convertfromraw --format VDI "$(BUILD_DIR)/openwrt-$(VERSION).img" "$(BUILD_DIR)/openwrt-$(VERSION).vdi"

.PHONY: vm
vm: $(BUILD_DIR)/$(VM_NAME).ovf ## Create VirtualBox machine image

$(BUILD_DIR)/$(VM_NAME).ovf $(BUILD_DIR)/$(VM_NAME)*.vmdk &: $(BUILD_DIR)/openwrt-$(VERSION).vdi
	rm -rf "$(BUILD_DIR)/$(VM_NAME).ovf" "$(BUILD_DIR)/$(VM_NAME)"*.vmdk
	VBoxManage createvm --name "$(VM_NAME)" --ostype "Linux_64" --register
	VBoxManage storagectl "$(VM_NAME)" --name SATA --add sata --controller IntelAHCI --portcount 1
	VBoxManage storageattach "$(VM_NAME)" --storagectl SATA --port 0 --device 0 --type hdd --medium "$(BUILD_DIR)/openwrt-$(VERSION).vdi"
	VBoxManage export "$(VM_NAME)" --output "$(BUILD_DIR)/$(VM_NAME).ovf"
	VBoxManage unregistervm "$(VM_NAME)" --delete

.PHONY: build
build: vm ## Build all boxes
	mkdir -p "$(OUTPUT_DIR)"
	packer build \
		-var "build_dir=$(BUILD_DIR)" \
		-var "output_dir=$(OUTPUT_DIR)" \
		-var "vm_name=$(VM_NAME)" \
		build.pkr.hcl

.PHONY: build-virtualbox
build-virtualbox: $(OUTPUT_DIR)/openwrt-$(VERSION)-virtualbox-ovf.box ## Build VirtualBox only

$(OUTPUT_DIR)/openwrt-$(VERSION)-virtualbox-ovf.box: vm
	packer build -only=virtualbox-ovf.openwrt-virtualbox \
		-var "build_dir=$(BUILD_DIR)" \
		-var "output_dir=$(OUTPUT_DIR)" \
		-var "vm_name=$(VM_NAME)" \
		build.pkr.hcl

.PHONY: build-libvirt
build-libvirt: $(OUTPUT_DIR)/openwrt-$(VERSION)-qemu.box ## Build Libvirt/Qemu Box only

$(OUTPUT_DIR)/openwrt-$(VERSION)-qemu.box: $(BUILD_DIR)/openwrt-$(VERSION).img
	packer build -only=qemu.openwrt-libvirt \
		-var "build_dir=$(BUILD_DIR)" \
		-var "output_dir=$(OUTPUT_DIR)" \
		-var "vm_name=$(VM_NAME)" \
		build.pkr.hcl

## Cleanup
.PHONY: clean
clean:
	rm -rf $(DIRS)

.PHONY: all
all: build shasums ## Build all boxes and print SHA sums

.PHONY: install-virtualbox
install-virtualbox: $(OUTPUT_DIR)/$(VM_NAME)-virtualbox-ovf.box ## Install Virtualbox box
	vagrant box add "$(VM_NAME)" "$(OUTPUT_DIR)/$(VM_NAME)-virtualbox-ovf.box" --force

.PHONY: shasums
shasums: ## Print SHA sums
	@echo ""
	@shasum -a 512 "$(OUTPUT_DIR)/$(VM_NAME)-*.box"

.PHONY: help
help: ## This help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' | sort