# docker-bake.hcl — unified build: builder-php compiled ONCE, cli+fpm share layers
#
# Default: linux/amd64
# Override:  docker buildx bake -f docker-bake.hcl all --set ARCH=arm64

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

group "default" {
  targets = ["all"]
}

group "all" {
  targets = ["cli", "fpm", "extension-sdk"]
}

group "multiarch" {
  targets = ["cli-amd64", "cli-arm64", "fpm-amd64", "fpm-arm64"]
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
}

target "builder-php" {
  inherits = ["_common"]
  target   = "builder-php"
}

target "extension-sdk" {
  inherits = ["_common"]
  target   = "extension-sdk"
  tags     = ["${REGISTRY}/${IMAGE_NAME}:${PHP_VERSION}-sdk-${ARCH}"]
}

target "cli" {
  inherits = ["_common"]
  target   = "cli"
  tags     = ["${REGISTRY}/${IMAGE_NAME}:${PHP_VERSION}-cli-${ARCH}"]
}

target "fpm" {
  inherits = ["_common"]
  target   = "fpm"
  tags     = ["${REGISTRY}/${IMAGE_NAME}:${PHP_VERSION}-fpm-${ARCH}"]
}

# Convenience targets for CI matrix (explicit arch, no variable override needed)
target "cli-amd64" {
  inherits = ["cli"]
  platforms = ["linux/amd64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:${PHP_VERSION}-cli"]
}

target "cli-arm64" {
  inherits = ["cli"]
  platforms = ["linux/arm64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:${PHP_VERSION}-cli-arm64"]
}

target "fpm-amd64" {
  inherits = ["fpm"]
  platforms = ["linux/amd64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:${PHP_VERSION}-fpm"]
}

target "fpm-arm64" {
  inherits = ["fpm"]
  platforms = ["linux/arm64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:${PHP_VERSION}-fpm-arm64"]
}

target "extension-sdk-amd64" {
  inherits = ["extension-sdk"]
  platforms = ["linux/amd64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:${PHP_VERSION}-sdk"]
}

target "extension-sdk-arm64" {
  inherits = ["extension-sdk"]
  platforms = ["linux/arm64"]
  tags      = ["${REGISTRY}/${IMAGE_NAME}:${PHP_VERSION}-sdk-arm64"]
}
