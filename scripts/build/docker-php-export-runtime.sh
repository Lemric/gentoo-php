#!/usr/bin/env bash
# docker-php-export-runtime — export minimal runtime overlay after extension installs
#
# Use in multi-stage Dockerfiles: build in *-build image, copy /export into cli/fpm.
#
# Usage (as root, after install-lib / docker-php-ext-install / docker-php-pie-install):
#   docker-php-export-runtime [/export]

set -euo pipefail

EXPORT="${1:-/export}"
PREFIX="/usr/local"

if [ "$(id -u)" -ne 0 ]; then
    echo "docker-php-export-runtime: must run as root (e.g. Dockerfile RUN)" >&2
    exit 1
fi

rm -rf "${EXPORT}"
mkdir -p "${EXPORT}${PREFIX}/lib/php/extensions" \
         "${EXPORT}${PREFIX}/etc/php/conf.d"

if [ -d "${PREFIX}/lib/php/extensions" ]; then
    cp -a "${PREFIX}/lib/php/extensions/." "${EXPORT}${PREFIX}/lib/php/extensions/"
fi
if [ -d "${PREFIX}/etc/php/conf.d" ]; then
    cp -a "${PREFIX}/etc/php/conf.d/." "${EXPORT}${PREFIX}/etc/php/conf.d/"
fi

/usr/local/bin/collect-runtime.sh "${EXPORT}" "${PREFIX}" export

echo ">>> docker-php-export-runtime: $(du -sh "${EXPORT}" | awk '{print $1}') -> ${EXPORT}"
