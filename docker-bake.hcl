# docker-bake.hcl — unified build: builder-php compiled ONCE, cli+fpm share layers
#
# Public tags (multi-arch): cli-8.5.8, fpm-8.5.8, cli-build-8.5.8, fpm-build-8.5.8
# Per-arch push tags (CI only): cli-8.5.8-amd64, …
#
# Local:  docker buildx bake -f docker-bake.hcl all --var ARCH=amd64 --load
# CI:     all-amd64 / all-arm64 groups → manifest job merges into cli-8.5.8

variable "PHP_VERSION" { default = "8.5.8" }
variable "PHP_GPG_KEYS" { default = "" }
variable "PHP_SHA256" { default = "" }
variable "REGISTRY" { default = "ghcr.io/lemric/gentoo-php" }
variable "IMAGE_NAME" { default = "php" }
variable "ARCH" { default = "amd64" }
variable "BUILD_JOBS" { default = "0" }
variable "EMERGE_JOBS" { default = "0" }
variable "BUILD_LOAD" { default = "0" }
variable "PORTAGE_TMPFS_SIZE" { default = "34359738368" }
variable "GENTOO_CACHE_ID" { default = "amd64" }
variable "GENTOO_SYNC" { default = "0" }
# Set to e.g. "gentoo-php-amd64" on GitHub Actions for cross-run layer cache
variable "CACHE_SCOPE" { default = "" }

group "default" {
  targets = ["all"]
}

group "all" {
  targets = ["cli", "fpm", "cli-build", "fpm-build"]
}

group "all-amd64" {
  targets = ["cli-amd64", "fpm-amd64", "cli-build-amd64", "fpm-build-amd64"]
}

group "all-arm64" {
  targets = ["cli-arm64", "fpm-arm64", "cli-build-arm64", "fpm-build-arm64"]
}

group "runtime" {
  targets = ["cli", "fpm"]
}

target "_common" {
  dockerfile = "docker/Dockerfile"
  context    = "."
  args = {
    PHP_VERSION         = PHP_VERSION
    PHP_GPG_KEYS        = PHP_GPG_KEYS
    PHP_SHA256          = PHP_SHA256
    BUILD_JOBS          = BUILD_JOBS
    EMERGE_JOBS         = EMERGE_JOBS
    BUILD_LOAD          = BUILD_LOAD
    PORTAGE_TMPFS_SIZE  = PORTAGE_TMPFS_SIZE
    GENTOO_CACHE_ID     = ARCH
    GENTOO_SYNC         = GENTOO_SYNC
  }
  platforms  = ["linux/${ARCH}"]
  # GHA cache: fast restore within 10 GB/repo limit; registry: durable fallback for heavy Gentoo layers
  cache-from = CACHE_SCOPE != "" ? [
    "type=gha,scope=${CACHE_SCOPE}",
    "type=registry,ref=${REGISTRY}/${IMAGE_NAME}:buildcache-${ARCH}",
  ] : []
  cache-to = CACHE_SCOPE != "" ? [
    "type=gha,mode=max,scope=${CACHE_SCOPE}",
    "type=registry,ref=${REGISTRY}/${IMAGE_NAME}:buildcache-${ARCH},mode=max",
  ] : []
}

target "builder-php" {
  inherits = ["_common"]
  target   = "builder-php"
}

target "cli" {
  inherits = ["_common"]
  target   = "cli"
  tags     = ["${REGISTRY}/${IMAGE_NAME}:cli-${PHP_VERSION}"]
}

target "fpm" {
  inherits = ["_common"]
  target   = "fpm"
  tags     = ["${REGISTRY}/${IMAGE_NAME}:fpm-${PHP_VERSION}"]
}

# Per-arch registry tags (merged into multi-arch manifests by CI)
target "cli-amd64" {
  inherits  = ["cli"]
  platforms = ["linux/amd64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:cli-${PHP_VERSION}-amd64"]
}

target "cli-arm64" {
  inherits  = ["cli"]
  platforms = ["linux/arm64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:cli-${PHP_VERSION}-arm64"]
}

target "fpm-amd64" {
  inherits  = ["fpm"]
  platforms = ["linux/amd64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:fpm-${PHP_VERSION}-amd64"]
}

target "fpm-arm64" {
  inherits  = ["fpm"]
  platforms = ["linux/arm64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:fpm-${PHP_VERSION}-arm64"]
}

target "cli-build" {
  inherits = ["_common"]
  target   = "cli-build"
  tags     = ["${REGISTRY}/${IMAGE_NAME}:cli-build-${PHP_VERSION}"]
}

target "fpm-build" {
  inherits = ["_common"]
  target   = "fpm-build"
  tags     = ["${REGISTRY}/${IMAGE_NAME}:fpm-build-${PHP_VERSION}"]
}

target "cli-build-amd64" {
  inherits  = ["cli-build"]
  platforms = ["linux/amd64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:cli-build-${PHP_VERSION}-amd64"]
}

target "cli-build-arm64" {
  inherits  = ["cli-build"]
  platforms = ["linux/arm64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:cli-build-${PHP_VERSION}-arm64"]
}

target "fpm-build-amd64" {
  inherits  = ["fpm-build"]
  platforms = ["linux/amd64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:fpm-build-${PHP_VERSION}-amd64"]
}

target "fpm-build-arm64" {
  inherits  = ["fpm-build"]
  platforms = ["linux/arm64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:fpm-build-${PHP_VERSION}-arm64"]
}
