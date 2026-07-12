#!/usr/bin/env bash
# harden-runtime.sh — final production lockdown for scratch runtime staging
#
# Usage: harden-runtime.sh <staging_root> [prefix=/usr/local]
#
# Removes shells, build tooling, setuid bits, and verifies attack surface.
set -euo pipefail

STAGING="${1:?staging root required}"
PREFIX="${2:-/usr/local}"

echo ">>> harden-runtime: ${STAGING}"

# No interactive shells or package managers in production runtime.
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

# Shell scripts and build-only helpers — production runs php/php-fpm directly.
for tool in \
    docker-php-entrypoint docker-php-healthcheck \
    docker-php-source docker-php-ext-configure docker-php-ext-install docker-php-ext-enable \
    docker-php-pie-install docker-php-pecl-install docker-php-env \
    install-lib merge-install-root.sh docker-php-install-env.sh \
    docker-php-install-cleanup.sh docker-php-export-runtime.sh \
    phpize php-config phpdbg pecl pear pie \
    configure-php.sh setup-fpm-config.sh fix-fpm-config.sh \
    collect-runtime.sh analyze-deps.sh bundle-install-stack.sh harden-runtime.sh; do
    rm -f "${STAGING}${PREFIX}/bin/${tool}" 2>/dev/null || true
done

# Drop stray shell scripts anywhere in staging (except whitelisted PHP probes).
while IFS= read -r -d '' script; do
    case "${script}" in
        *"/libexec/php/"*.php)
            continue
            ;;
    esac
    if head -c 2 "${script}" 2>/dev/null | grep -q '^#!'; then
        rm -f "${script}"
    fi
done < <(find "${STAGING}" -type f -print0 2>/dev/null || true)

# Remove development templates and docs.
rm -f \
    "${STAGING}${PREFIX}/etc/php/php.ini-development" \
    "${STAGING}${PREFIX}/etc/php/php.ini-production" \
    2>/dev/null || true
find "${STAGING}${PREFIX}/etc" -type f \( -name '*.default' -o -name '*.dist' -o -name '*.example' \) -delete 2>/dev/null || true

# Strip setuid/setgid/sticky abuse vectors on non-/tmp paths.
find "${STAGING}" -path "${STAGING}/tmp" -prune -o -type f -perm /6000 -exec chmod u-s,g-s {} + 2>/dev/null || true

# Read-only rootfs posture: no world-writable files outside /tmp.
find "${STAGING}" -path "${STAGING}/tmp/*" -prune -o -type f -perm -0002 -exec chmod o-w {} + 2>/dev/null || true
find "${STAGING}" -path "${STAGING}/tmp" -prune -o -type d -perm -0002 -exec chmod o-w {} + 2>/dev/null || true

# Config and binaries: no write bit for group/other.
find "${STAGING}${PREFIX}" -type f -exec chmod go-w {} + 2>/dev/null || true
find "${STAGING}/etc" -type f -exec chmod go-w {} + 2>/dev/null || true

# Executable allowlist verification.
allowed_exe=()
while IFS= read -r -d '' elf; do
    allowed_exe+=("${elf#${STAGING}}")
done < <(find "${STAGING}" -type f -perm -111 -print0 2>/dev/null || true)

echo ">>> harden-runtime: executables (${#allowed_exe[@]}):"
printf '    %s\n' "${allowed_exe[@]}" | sort -u | head -40

# Fail closed on forbidden artifacts.
forbidden_patterns=(
    '/bin/sh'
    '/bin/busybox'
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

if find "${STAGING}" \( -name 'busybox' -o -name 'bash' -o -name 'sh' \) | grep -q .; then
    echo "harden-runtime: shell binary detected" >&2
    find "${STAGING}" \( -name 'busybox' -o -name 'bash' -o -name 'sh' \) >&2
    exit 1
fi

echo ">>> harden-runtime: OK"
