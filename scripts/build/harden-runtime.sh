#!/usr/bin/env bash
# harden-runtime.sh — final production lockdown for scratch runtime staging
#
# Usage: harden-runtime.sh <staging_root> [prefix=/usr/local] [profile=fpm|cli|export]
#
# Staging never contains /bin/sh — CLI shell lives in scratch-runtime-cli rootfs layer.
set -euo pipefail

STAGING="${1:?staging root required}"
PREFIX="${2:-/usr/local}"
PROFILE="${3:-fpm}"

echo ">>> harden-runtime: ${STAGING} (profile=${PROFILE})"

rm -rf \
    "${STAGING}/bin" \
    "${STAGING}/sbin" \
    "${STAGING}/usr/bin" \
    "${STAGING}/usr/sbin" \
    "${STAGING}/usr/src" \
    "${STAGING}${PREFIX}/libexec/install" \
    "${STAGING}${PREFIX}/include" \
    "${STAGING}${PREFIX}/lib/php/build" \
    "${STAGING}${PREFIX}/lib/php/test" \
    "${STAGING}${PREFIX}/share" \
    "${STAGING}${PREFIX}/var" \
    2>/dev/null || true

for tool in \
    docker-php-healthcheck \
    docker-php-source docker-php-ext-configure docker-php-ext-install docker-php-ext-enable \
    docker-php-pie-install docker-php-pecl-install docker-php-env \
    install-lib merge-install-root.sh docker-php-install-env.sh \
    docker-php-install-cleanup.sh docker-php-export-runtime.sh \
    phpize php-config phpdbg pecl pear pie \
    configure-php.sh setup-fpm-config.sh fix-fpm-config.sh \
    collect-runtime.sh analyze-deps.sh bundle-install-stack.sh harden-runtime.sh; do
    rm -f "${STAGING}${PREFIX}/bin/${tool}" 2>/dev/null || true
done

# CLI keeps upstream entrypoint in final image (scratch-runtime-cli); never in PHP prefix staging.
if [ "${PROFILE}" != "cli" ]; then
    rm -f "${STAGING}${PREFIX}/bin/docker-php-entrypoint" 2>/dev/null || true
fi

while IFS= read -r -d '' script; do
    case "${script}" in
        *.php)
            continue
            ;;
    esac
    if head -c 2 "${script}" 2>/dev/null | grep -q '^#!'; then
        rm -f "${script}"
    fi
done < <(find "${STAGING}" -type f -print0 2>/dev/null || true)

rm -f \
    "${STAGING}${PREFIX}/etc/php/php.ini-development" \
    "${STAGING}${PREFIX}/etc/php/php.ini-production" \
    2>/dev/null || true
find "${STAGING}${PREFIX}/etc" -type f \( -name '*.default' -o -name '*.dist' -o -name '*.example' \) -delete 2>/dev/null || true

find "${STAGING}" -path "${STAGING}/tmp" -prune -o -type f -perm /6000 -exec chmod u-s,g-s {} + 2>/dev/null || true
find "${STAGING}" -path "${STAGING}/tmp/*" -prune -o -type f -perm -0002 -exec chmod o-w {} + 2>/dev/null || true
find "${STAGING}" -path "${STAGING}/tmp" -prune -o -type d -perm -0002 -exec chmod o-w {} + 2>/dev/null || true
find "${STAGING}${PREFIX}" -type f -exec chmod go-w {} + 2>/dev/null || true
find "${STAGING}/etc" -type f -exec chmod go-w {} + 2>/dev/null || true

forbidden_patterns=(
    '/usr/bin/emerge'
    '/usr/bin/gcc'
    "${PREFIX}/bin/pie"
    "${PREFIX}/bin/phpize"
    "${PREFIX}/libexec/install"
)

for path in "${forbidden_patterns[@]}"; do
    if [ -e "${STAGING}${path}" ]; then
        echo "harden-runtime: forbidden path present: ${path}" >&2
        exit 1
    fi
done

if find "${STAGING}" -type f -perm /6000 | grep -q .; then
    echo "harden-runtime: setuid/setgid binaries remain" >&2
    find "${STAGING}" -type f -perm /6000 >&2
    exit 1
fi

# Staging must not ship a full shell — CLI /bin/sh comes from scratch-runtime-cli; FPM from scratch-runtime (entrypoint only).
if find "${STAGING}" \( -name 'busybox' -o -name 'bash' -o -name 'sh' \) | grep -q .; then
    echo "harden-runtime: shell binary detected in staging" >&2
    find "${STAGING}" \( -name 'busybox' -o -name 'bash' -o -name 'sh' \) >&2
    exit 1
fi

echo ">>> harden-runtime: OK"
