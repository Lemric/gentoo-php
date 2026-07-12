#!/usr/bin/env bash
# collect-runtime.sh — minimal scratch rootfs assembly via dependency closure
#
# Usage: collect-runtime.sh <staging_root> <prefix> [--variant cli|fpm]
#
# 1. Copies prefix tree (caller must have done cp -a /usr/local -> staging)
# 2. BFS ldd closure for php binaries + extension .so files
# 3. Copies dynamic linker for target architecture
# 4. Strips debug symbols from copied binaries
# 5. Removes build artifacts (headers, pkgconfig, man, doc)

set -euo pipefail

STAGING="${1:?staging root required}"
PREFIX="${2:-/usr/local}"
VARIANT="${3:-cli}"

if [[ "${VARIANT}" != "cli" && "${VARIANT}" != "fpm" ]]; then
    echo "collect-runtime: variant must be cli or fpm" >&2
    exit 1
fi

copy_with_path() {
    local src="$1"
    local dst="${STAGING}${src}"
    if [ ! -e "${dst}" ]; then
        mkdir -p "$(dirname "${dst}")"
        cp -aL "${src}" "${dst}"
    fi
}

# ld.so searches /lib*, /usr/lib* — not /usr/lib/gcc/... unless RUNPATH is set.
install_gcc_runtime() {
    local libgcc="" libdir candidate
    while IFS= read -r candidate; do
        file -b "${candidate}" 2>/dev/null | grep -q 'ELF' || continue
        libgcc="${candidate}"
        break
    done < <(find /usr/lib/gcc -name 'libgcc_s.so.1' -type f 2>/dev/null | sort -V)

    [ -n "${libgcc}" ] || {
        echo "collect-runtime: warning: libgcc_s.so.1 ELF not found" >&2
        return 0
    }

    case "$(uname -m)" in
        x86_64|aarch64) libdir="${STAGING}/usr/lib64" ;;
        *) libdir="${STAGING}/usr/lib" ;;
    esac
    mkdir -p "${libdir}"
    cp -a "${libgcc}" "${libdir}/libgcc_s.so.1"
    echo ">>> collect-runtime: libgcc_s -> ${libdir}/libgcc_s.so.1 (from ${libgcc})"
}

resolve_deps() {
    local target="$1"
    ldd "${target}" 2>/dev/null | awk '
        /=>/ { if ($3 ~ /^\//) print $3; next }
        /^\// { print $1 }
    ' | sort -u
}

TARGETS=()
if [ "${VARIANT}" = "cli" ]; then
    [ -f "${PREFIX}/bin/php" ] && TARGETS+=("${PREFIX}/bin/php")
else
    [ -f "${PREFIX}/sbin/php-fpm" ] && TARGETS+=("${PREFIX}/sbin/php-fpm")
    # FPM workers reuse php binary for some operations
    [ -f "${PREFIX}/bin/php" ] && TARGETS+=("${PREFIX}/bin/php")
fi

if [ -d "${PREFIX}/lib/php/extensions" ]; then
    while IFS= read -r -d '' so; do
        TARGETS+=("${so}")
    done < <(find "${PREFIX}/lib/php/extensions" -name '*.so' -print0 2>/dev/null || true)
fi

if [ "${#TARGETS[@]}" -eq 0 ]; then
    echo "collect-runtime: no binaries found under ${PREFIX} for variant ${VARIANT}" >&2
    exit 1
fi

declare -A SEEN
QUEUE=("${TARGETS[@]}")

while [ "${#QUEUE[@]}" -gt 0 ]; do
    current="${QUEUE[0]}"
    QUEUE=("${QUEUE[@]:1}")
    for lib in $(resolve_deps "${current}"); do
        if [ -z "${SEEN[$lib]:-}" ]; then
            SEEN[$lib]=1
            copy_with_path "${lib}"
            QUEUE+=("${lib}")
        fi
    done
done

# Dynamic linker — architecture-aware
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)
        for ldpath in /lib64/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2; do
            [ -e "${ldpath}" ] && copy_with_path "${ldpath}"
        done
        ;;
    aarch64)
        for ldpath in /lib/ld-linux-aarch64.so.1 /lib64/ld-linux-aarch64.so.1; do
            [ -e "${ldpath}" ] && copy_with_path "${ldpath}"
        done
        ;;
    *)
        echo "collect-runtime: unsupported architecture ${ARCH}" >&2
        exit 1
        ;;
esac

# Strip executables and shared libraries in staging (libgcc_s must not be stripped)
find "${STAGING}" -type f \( -perm -111 -o -name '*.so*' \) \
    ! -path '*/libgcc_s.so*' \
    -exec strip --strip-unneeded {} + 2>/dev/null || true

# ld.so searches /usr/lib64 — install after strip; gcc stores it under /usr/lib/gcc/...
install_gcc_runtime

# Remove non-runtime artifacts from prefix copy
for pattern in include pkgconfig share/man share/doc share/info share/gtk-doc \
    share/locale share/zoneinfo/leap-seconds.list lib/*.a lib/*.la; do
    rm -rf "${STAGING}${PREFIX}/${pattern}" 2>/dev/null || true
done

# CLI variant: drop FPM artifacts (single unified build, pruned here)
if [ "${VARIANT}" = "cli" ]; then
    rm -f "${STAGING}${PREFIX}/sbin/php-fpm" 2>/dev/null || true
    rm -rf "${STAGING}${PREFIX}/etc/php-fpm.d" "${STAGING}${PREFIX}/etc/php-fpm.conf" 2>/dev/null || true
    rm -f "${STAGING}${PREFIX}/etc/php/conf.d/opcache-production.ini" 2>/dev/null || true
    rm -f "${STAGING}${PREFIX}/etc/php/conf.d/docker-fpm.ini" 2>/dev/null || true
fi

# FPM variant: drop CLI-only debug tooling (official fpm image has no phpdbg)
if [ "${VARIANT}" = "fpm" ]; then
    rm -f "${STAGING}${PREFIX}/bin/phpdbg" 2>/dev/null || true
fi

# Remove build/SDK artifacts — never ship in scratch runtime
for tool in phpize php-config pecl pear docker-php-source docker-php-ext-configure \
    docker-php-ext-install docker-php-ext-enable docker-php-pecl-install \
    docker-php-env install-lib configure-php.sh setup-fpm-config.sh \
    collect-runtime.sh analyze-deps.sh; do
    rm -f "${STAGING}${PREFIX}/bin/${tool}" 2>/dev/null || true
done
rm -rf "${STAGING}${PREFIX}/include" \
       "${STAGING}${PREFIX}/lib/php/build" \
       "${STAGING}${PREFIX}/lib/php/test" \
       "${STAGING}${PREFIX}/share" \
       "${STAGING}${PREFIX}/var" 2>/dev/null || true

echo ">>> collect-runtime: ${#SEEN[@]} shared libraries, variant=${VARIANT}"
du -sh "${STAGING}" | awk '{print ">>> staging size:", $1}'
