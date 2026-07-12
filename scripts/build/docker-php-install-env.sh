#!/usr/bin/env bash
# shellcheck disable=SC2034
# docker-php-install-env.sh — PATH + Portage for in-image extension installs (cli/fpm)

INSTALL_ROOT="${INSTALL_ROOT:-/usr/local/libexec/install}"
PORTAGE_ROOT="${INSTALL_ROOT}/portage"

export PATH="${INSTALL_ROOT}/usr/bin:${INSTALL_ROOT}/usr/sbin:${PATH}"
export PORTAGE_CONFIGROOT="${PORTAGE_ROOT}"
export PORTDIR="${PORTAGE_ROOT}/var/db/repos/gentoo"
export DISTDIR="/tmp/gentoo-distfiles"
export PKGDIR="${INSTALL_ROOT}/var/cache/binhost"
export PORTAGE_TMPDIR="/tmp/portage"
export FEATURES="${FEATURES:-} getbinpkg binpkg-multi-instance -sandbox -network-sandbox -pid-sandbox"

mkdir -p "${DISTDIR}" "${PKGDIR}" "${PORTAGE_TMPDIR}" 2>/dev/null || true
