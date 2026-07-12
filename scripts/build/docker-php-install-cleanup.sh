#!/usr/bin/env bash
# docker-php-install-cleanup.sh — mandatory post-install hygiene (OWASP / minimal surface)
#
# Usage: docker-php-install-cleanup [--keep-source]
#
# Called automatically by install-lib, docker-php-pie-install, docker-php-ext-install.
set -euo pipefail

KEEP_SOURCE=0
[ "${1:-}" = "--keep-source" ] && KEEP_SOURCE=1

if [ "${KEEP_SOURCE}" -eq 0 ] && command -v docker-php-source >/dev/null 2>&1; then
    docker-php-source delete 2>/dev/null || true
fi

rm -rf \
    /tmp/pie /tmp/pear /tmp/pear-build-* \
    /tmp/php-ext-* /tmp/install-lib.* \
    /root/.cache/pie /root/.composer /root/.pearrc \
    2>/dev/null || true

find /tmp/portage /tmp/gentoo-distfiles -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

rm -rf /usr/local/lib/php/test 2>/dev/null || true
find /usr/local/lib/php/extensions -name '*.la' -delete 2>/dev/null || true
find /usr/local/lib/php/extensions -name '*.so' -exec strip --strip-unneeded {} + 2>/dev/null || true

# Remove accidental build artifacts under prefix (never ship in runtime layer)
find /usr/local/include -type f -name '*.h' -path '*/ext/*' -delete 2>/dev/null || true

echo ">>> docker-php-install-cleanup: done"
