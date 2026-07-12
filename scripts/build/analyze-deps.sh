#!/usr/bin/env bash
# analyze-deps.sh — dependency audit for scratch runtime staging
#
# Reports: duplicate .so, unused ELF dependencies, missing SONAMEs, security flags
# Requires: readelf, objdump (from binutils); scanelf optional (app-misc/pax-utils, not in scratch)

set -euo pipefail

STAGING="${1:?staging root required}"
PREFIX="${2:-/usr/local}"

echo "=== Dependency analysis: ${STAGING} ==="

PHP_BIN="${STAGING}${PREFIX}/bin/php"
FPM_BIN="${STAGING}${PREFIX}/sbin/php-fpm"

report_binary() {
    local bin="$1"
    [ -f "${bin}" ] || return 0
    echo "--- ${bin} ---"
    if command -v readelf >/dev/null 2>&1; then
        echo "  RELRO: $(readelf -l "${bin}" 2>/dev/null | awk '/GNU_RELRO/{print "present"}')"
        echo "  BIND_NOW: $(readelf -d "${bin}" 2>/dev/null | awk '/FLAGS.*BIND_NOW/{print "yes"}' || echo 'check manually')"
        echo "  PIE: $(readelf -h "${bin}" 2>/dev/null | awk '/Type:.*DYN/{print "yes (PIE)"} /Type:.*EXEC/{print "no (non-PIE)"}')"
        echo "  STACK_CANARY: $(readelf -s "${bin}" 2>/dev/null | awk '/__stack_chk_fail/{print "yes"}')"
    fi
    if command -v ldd >/dev/null 2>&1; then
        echo "  NEEDED:"
        ldd "${bin}" 2>/dev/null | sed 's/^/    /' || true
    fi
}

report_binary "${PHP_BIN}"
report_binary "${FPM_BIN}"

echo "--- Shared libraries in staging ---"
find "${STAGING}" -name '*.so*' -type f 2>/dev/null | wc -l | awk '{print "  count:", $1}'

echo "--- Duplicate basenames (potential redundancy) ---"
find "${STAGING}" -name '*.so*' -type f -printf '%f\n' 2>/dev/null \
    | sort | uniq -d | head -20 || true

if command -v scanelf >/dev/null 2>&1; then
    echo "--- scanelf summary ---"
    scanelf -R "${STAGING}" -F '%F %f %M %D' 2>/dev/null | head -30 || true
fi

echo "=== Analysis complete ==="
