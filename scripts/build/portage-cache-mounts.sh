#!/usr/bin/env bash
# Emit BuildKit mount flags for persistent Gentoo caches on the build host.
# Usage in Dockerfile RUN (paths must exist on docker host — make setup-cache-dirs):
#   RUN --mount=type=bind,source=${GENTOO_DISTFILES},target=/var/cache/distfiles \
#       --mount=type=bind,source=${GENTOO_BINHOST},target=/var/cache/binhost \
#       --mount=type=bind,source=${GENTOO_CCACHE},target=/var/cache/ccache \
#       ...
# This file documents the contract; mounts are inlined in docker/Dockerfile.
