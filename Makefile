# =============================================================================
# PHP 8.5 Gentoo Scratch Images
# =============================================================================

DOCKERFILE := docker/Dockerfile
PHP_VERSION ?= 8.5.8
REGISTRY ?= ghcr.io/lemric/gentoo-php
IMAGE_NAME ?= php
ARCH ?= amd64
PLATFORM := linux/$(ARCH)
export PHP_GPG_KEYS ?=
# Optional: defaults match docker-library/php 8.5; override when php.net adds release signers

# Tag suffix: amd64 = no suffix (default), arm64 = -arm64
ifeq ($(ARCH),amd64)
IMAGE_TAG_SUFFIX :=
else
IMAGE_TAG_SUFFIX := -$(ARCH)
endif

# Parallel build tuning (0 = auto-detect nproc inside container)
BUILD_JOBS ?= 0
EMERGE_JOBS ?= 0
BUILD_LOAD ?= 0
# BuildKit cache ids (persist in gentoo-fast builder on docker-builder)
GENTOO_CACHE_BASE ?= /var/cache/gentoo-docker
PORTAGE_TMPFS_SIZE ?= 34359738368
GENTOO_SYNC ?= 0
# Remote build host (Mac → ssh docker-builder); empty = local docker
DOCKER_CONTEXT ?= remote-builder
# gentoo-fast = BuildKit container on docker-builder (max-parallelism=32, persistent cache mounts)
BUILDX_BUILDER ?= $(if $(filter remote-builder,$(DOCKER_CONTEXT)),gentoo-fast,$(if $(DOCKER_CONTEXT),$(DOCKER_CONTEXT),default))
BUILDX_CONFIG := $(CURDIR)/scripts/ops/buildkitd.toml

DOCKER := docker $(if $(DOCKER_CONTEXT),--context $(DOCKER_CONTEXT),)

PARALLEL_ARGS := \
	--build-arg BUILD_JOBS=$(BUILD_JOBS) \
	--build-arg EMERGE_JOBS=$(EMERGE_JOBS) \
	--build-arg BUILD_LOAD=$(BUILD_LOAD) \
	--build-arg PORTAGE_TMPFS_SIZE=$(PORTAGE_TMPFS_SIZE) \
	--build-arg GENTOO_CACHE_ID=$(ARCH) \
	--build-arg GENTOO_SYNC=$(GENTOO_SYNC)

DOCKER_BUILD := DOCKER_BUILDKIT=1 $(DOCKER) buildx build \
	--builder $(BUILDX_BUILDER) \
	--platform $(PLATFORM) \
	--load

.PHONY: help all cli fpm sdk verify clean bake-all cli-fast fpm-fast all-fast setup-builder setup-cache-dirs
.PHONY: builder-base toolchain php-builder builder-php collect-cli collect-fpm scratch-runtime

help:
	@echo "Gentoo PHP $(PHP_VERSION) — unified scratch image build"
	@echo ""
	@echo "  make all          Build cli + fpm (bake, shared builder-php)"
	@echo "  make cli          Build cli scratch image"
	@echo "  make fpm          Build fpm scratch image"
	@echo "  make sdk          Extension SDK image"
	@echo "  make verify       Full test suite"
	@echo ""
	@echo "Variables:"
	@echo "  ARCH=amd64        Target architecture (default: amd64)"
	@echo "                    Supported: amd64, arm64"
	@echo "  BUILD_JOBS=0      make -j per package (0 = auto: nproc-4)"
	@echo "  EMERGE_JOBS=0     emerge --jobs (0 = auto: nproc/8, max 8)"
	@echo "  BUILD_LOAD=0      load-average cap (0 = auto: nproc*1.25)"
	@echo "  DOCKER_CONTEXT=   docker context (default: remote-builder)"
	@echo "  BUILDX_BUILDER=   default: gentoo-fast (persistent BuildKit cache mounts)"
	@echo "  GENTOO_SYNC=0     skip webrsync when tree exists in cached layer"
	@echo ""
	@echo "  make setup-builder   Verify buildx builder + cache dirs on build host"
	@echo "  make setup-cache-dirs  Create persistent emerge/ccache dirs on build host"
	@echo "  make cli-fast     BUILD_JOBS=28 EMERGE_JOBS=4 BUILD_LOAD=36"
	@echo ""
	@echo "Examples:"
	@echo "  make cli                          # linux/amd64 (default)"
	@echo "  make cli ARCH=arm64               # linux/arm64"
	@echo "  make all ARCH=arm64"
	@echo ""
	@echo "  PHP_GPG_KEYS=     optional; keys auto-fetched (default: docker-library 8.5)"

_check_keys:
	@:

_check_arch:
	@case "$(ARCH)" in amd64|arm64) ;; \
	*) echo "ERROR: unsupported ARCH=$(ARCH), use amd64 or arm64" >&2; exit 1 ;; \
	esac

all: _check_keys _check_arch bake-all

bake-all: _check_arch
	$(DOCKER) buildx bake --builder $(BUILDX_BUILDER) --load \
		--provenance=false --sbom=false \
		--file docker-bake.hcl all \
		--var ARCH=$(ARCH) \
		--var REGISTRY=$(REGISTRY) \
		--var IMAGE_NAME=$(IMAGE_NAME) \
		--var PHP_VERSION=$(PHP_VERSION) \
		--var PHP_GPG_KEYS="$(PHP_GPG_KEYS)" \
		--var BUILD_JOBS=$(BUILD_JOBS) \
		--var EMERGE_JOBS=$(EMERGE_JOBS) \
		--var BUILD_LOAD=$(BUILD_LOAD) \
		--var PORTAGE_TMPFS_SIZE=$(PORTAGE_TMPFS_SIZE) \
		--var GENTOO_SYNC=$(GENTOO_SYNC)

cli-fast fpm-fast all-fast:
	$(MAKE) $(subst -fast,,$@) BUILD_JOBS=28 EMERGE_JOBS=4 BUILD_LOAD=36

setup-builder: setup-cache-dirs
	@$(DOCKER) buildx inspect $(BUILDX_BUILDER) >/dev/null 2>&1 && \
		echo ">>> buildx builder '$(BUILDX_BUILDER)' OK (context=$(DOCKER_CONTEXT))" || \
	( echo ">>> creating buildx builder '$(BUILDX_BUILDER)'..." && \
	  $(DOCKER) buildx rm -f $(BUILDX_BUILDER) 2>/dev/null || true; \
	  $(DOCKER) buildx create --name $(BUILDX_BUILDER) \
	    --driver docker-container \
	    --driver-opt network=host \
	    --driver-opt image=moby/buildkit:latest \
	    --buildkitd-flags "--allow-insecure-entitlement=network.host" \
	    --config $(BUILDX_CONFIG) \
	    --platform linux/amd64,linux/arm64 \
	    --use --bootstrap )
	@$(DOCKER) buildx use $(BUILDX_BUILDER)

setup-cache-dirs:
	@ssh docker-builder 'sudo install -d -m 1777 \
		$(GENTOO_CACHE_BASE)/distfiles \
		$(GENTOO_CACHE_BASE)/binhost \
		$(GENTOO_CACHE_BASE)/ccache-amd64 \
		$(GENTOO_CACHE_BASE)/ccache-arm64'
	@echo ">>> cache dirs ready under $(GENTOO_CACHE_BASE) on docker-builder"

cli: _check_keys _check_arch
	$(DOCKER_BUILD) -f $(DOCKERFILE) --target cli \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg PHP_GPG_KEYS="$(PHP_GPG_KEYS)" \
		$(PARALLEL_ARGS) \
		-t $(IMAGE_NAME):$(PHP_VERSION)-cli$(IMAGE_TAG_SUFFIX) \
		.

fpm: _check_keys _check_arch
	$(DOCKER_BUILD) -f $(DOCKERFILE) --target fpm \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg PHP_GPG_KEYS="$(PHP_GPG_KEYS)" \
		$(PARALLEL_ARGS) \
		-t $(IMAGE_NAME):$(PHP_VERSION)-fpm$(IMAGE_TAG_SUFFIX) \
		.

sdk: _check_keys _check_arch
	$(DOCKER_BUILD) -f $(DOCKERFILE) --target extension-sdk \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg PHP_GPG_KEYS="$(PHP_GPG_KEYS)" \
		$(PARALLEL_ARGS) \
		-t $(IMAGE_NAME):$(PHP_VERSION)-sdk$(IMAGE_TAG_SUFFIX) \
		.

builder-base toolchain php-builder builder-php extension-sdk collect-cli collect-fpm scratch-runtime: _check_arch
	$(DOCKER_BUILD) -f $(DOCKERFILE) --target $@ \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg PHP_GPG_KEYS="$(PHP_GPG_KEYS)" \
		$(PARALLEL_ARGS) \
		-t gentoo-php/$@:$(ARCH) \
		.

verify: _check_arch
	ARCH=$(ARCH) PLATFORM=$(PLATFORM) PHP_VERSION=$(PHP_VERSION) ./scripts/verify-build.sh

clean:
	-docker rmi \
		$(IMAGE_NAME):$(PHP_VERSION)-cli \
		$(IMAGE_NAME):$(PHP_VERSION)-cli-arm64 \
		$(IMAGE_NAME):$(PHP_VERSION)-fpm \
		$(IMAGE_NAME):$(PHP_VERSION)-fpm-arm64 \
		$(IMAGE_NAME):$(PHP_VERSION)-sdk \
		$(IMAGE_NAME):$(PHP_VERSION)-sdk-arm64 \
		2>/dev/null
