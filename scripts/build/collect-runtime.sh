#!/usr/bin/env bash
# collect-runtime.sh — minimal scratch rootfs assembly via dependency closure
#
# Usage: collect-runtime.sh <staging_root> <prefix> <variant> [mode]
#
# variant: cli | fpm | export
# mode:    runtime (default) | build
#
# runtime — production scratch (no install stack, no headers, no build tools)
# build   — extension build image (keeps PIE/phpize/portage bundle under libexec/install)
# export  — ldd closure for extension .so only (multi-stage COPY overlay)

set -euo pipefail

STAGING="${1:?staging root required}"
PREFIX="${2:-/usr/local}"
VARIANT="${3:-cli}"
MODE="${4:-runtime}"

case "${VARIANT}" in
    cli|fpm|export) ;;
    *)
        echo "collect-runtime: variant must be cli, fpm, or export" >&2
        exit 1
        ;;
esac

case "${MODE}" in
    runtime|build) ;;
    *)
        echo "collect-runtime: mode must be runtime or build" >&2
        exit 1
        ;;
esac

if [ "${VARIANT}" = "export" ]; then
    MODE="runtime"
fi

copy_with_path() {
    local src="$1"
    local dst="${STAGING}${src}"
    if [ ! -e "${dst}" ]; then
        mkdir -p "$(dirname "${dst}")"
        cp -aL "${src}" "${dst}"
    fi
}

resolve_deps() {
    local target="$1"
    ldd "${target}" 2>/dev/null | awk '
        /=>/ { if ($3 ~ /^\//) print $3; next }
        /^\// { print $1 }
    ' | sort -u
}

declare -A SEEN

copy_lib_closure() {
    local src="$1"
    local resolved queue dep lib
    resolved="$(readlink -f "${src}" 2>/dev/null || echo "${src}")"
    copy_with_path "${src}"
    queue=("${resolved}")
    while [ "${#queue[@]}" -gt 0 ]; do
        dep="${queue[0]}"
        queue=("${queue[@]:1}")
        [ -n "${dep}" ] || continue
        [ -n "${SEEN[$dep]:-}" ] && continue
        SEEN[$dep]=1
        copy_with_path "${dep}"
        for lib in $(resolve_deps "${dep}"); do
            queue+=("${lib}")
        done
    done
}

install_openssl_runtime() {
    local libpath
    for libpath in \
        /usr/lib64/libssl.so.3 /usr/lib64/libcrypto.so.3 \
        /lib64/libssl.so.3 /lib64/libcrypto.so.3 \
        /usr/lib/libssl.so.3 /usr/lib/libcrypto.so.3; do
        [ -e "${libpath}" ] || continue
        echo ">>> collect-runtime: ensuring ${libpath}"
        copy_lib_closure "${libpath}"
    done
}

staging_library_path() {
    printf '%s' \
        "${STAGING}/usr/lib64:${STAGING}/lib64:${STAGING}/usr/lib:${STAGING}/lib"
}

staging_loader() {
    case "$(uname -m)" in
        x86_64)
            for c in "${STAGING}/lib64/ld-linux-x86-64.so.2" "${STAGING}/lib/ld-linux-x86-64.so.2"; do
                [ -x "${c}" ] && echo "${c}" && return 0
            done
            ;;
        aarch64)
            for c in "${STAGING}/lib/ld-linux-aarch64.so.1" "${STAGING}/lib64/ld-linux-aarch64.so.1"; do
                [ -x "${c}" ] && echo "${c}" && return 0
            done
            ;;
    esac
    return 1
}

verify_staging_openssl() {
    local loader php libpath
    loader="$(staging_loader)" || return 0
    php="${STAGING}${PREFIX}/bin/php"
    [ -x "${php}" ] || return 0
    libpath="$(staging_library_path)"

    echo ">>> collect-runtime: verifying openssl in staging"
    "${loader}" --library-path "${libpath}" "${php}" -r '
        if (!extension_loaded("openssl")) {
            fwrite(STDERR, "openssl extension not loaded\n");
            exit(1);
        }
        if (!defined("OPENSSL_VERSION_TEXT")) {
            fwrite(STDERR, "OPENSSL_VERSION_TEXT unavailable\n");
            exit(1);
        }
        echo OPENSSL_VERSION_TEXT, PHP_EOL;
    '
}

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

purge_runtime_install_artifacts() {
    rm -rf "${STAGING}${PREFIX}/libexec/install" \
           "${STAGING}${PREFIX}/include" \
           "${STAGING}${PREFIX}/lib/php/build" \
           "${STAGING}${PREFIX}/lib/php/test" \
           "${STAGING}${PREFIX}/share" \
           "${STAGING}${PREFIX}/var" \
           "${STAGING}/usr/src" 2>/dev/null || true

    for tool in phpize php-config pecl pear pie docker-php-source docker-php-ext-configure \
        docker-php-ext-install docker-php-ext-enable docker-php-pie-install docker-php-pecl-install \
        docker-php-env install-lib merge-install-root.sh docker-php-install-env.sh \
        docker-php-install-cleanup.sh docker-php-export-runtime.sh; do
        rm -f "${STAGING}${PREFIX}/bin/${tool}" 2>/dev/null || true
    done
}

TARGETS=()
if [ "${VARIANT}" = "export" ]; then
    if [ -d "${PREFIX}/lib/php/extensions" ]; then
        while IFS= read -r -d '' so; do
            TARGETS+=("${so}")
        done < <(find "${PREFIX}/lib/php/extensions" -name '*.so' -print0 2>/dev/null || true)
    fi
elif [ "${VARIANT}" = "cli" ]; then
    [ -f "${PREFIX}/bin/php" ] && TARGETS+=("${PREFIX}/bin/php")
else
    [ -f "${PREFIX}/sbin/php-fpm" ] && TARGETS+=("${PREFIX}/sbin/php-fpm")
    [ -f "${PREFIX}/bin/php" ] && TARGETS+=("${PREFIX}/bin/php")
fi

if [ "${VARIANT}" != "export" ] && [ -d "${PREFIX}/lib/php/extensions" ]; then
    while IFS= read -r -d '' so; do
        TARGETS+=("${so}")
    done < <(find "${PREFIX}/lib/php/extensions" -name '*.so' -print0 2>/dev/null || true)
fi

if [ "${#TARGETS[@]}" -eq 0 ]; then
    if [ "${VARIANT}" = "export" ]; then
        echo ">>> collect-runtime: export — no extension .so files (config-only overlay)"
    else
        echo "collect-runtime: no binaries found under ${PREFIX} for variant ${VARIANT}" >&2
        exit 1
    fi
fi

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

if [ "${VARIANT}" != "export" ]; then
    install_openssl_runtime
fi

if [ "${VARIANT}" != "export" ]; then
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
fi

find "${STAGING}" -type f \( -perm -111 -o -name '*.so*' \) \
    ! -path '*/libexec/install/*' \
    ! -path '*/libgcc_s.so*' \
    ! -path '*/libssl.so*' \
    ! -path '*/libcrypto.so*' \
    -exec strip --strip-unneeded {} + 2>/dev/null || true

if [ "${VARIANT}" != "export" ]; then
    install_gcc_runtime
fi

if [ "${VARIANT}" = "export" ]; then
    echo ">>> collect-runtime: export overlay, ${#SEEN[@]} shared libraries"
    du -sh "${STAGING}" | awk '{print ">>> staging size:", $1}'
    exit 0
fi

for pattern in pkgconfig share/man share/doc share/info share/gtk-doc \
    share/locale share/zoneinfo/leap-seconds.list lib/*.a lib/*.la; do
    rm -rf "${STAGING}${PREFIX}/${pattern}" 2>/dev/null || true
done

for tool in configure-php.sh setup-fpm-config.sh fix-fpm-config.sh \
    collect-runtime.sh analyze-deps.sh bundle-install-stack.sh; do
    rm -f "${STAGING}${PREFIX}/bin/${tool}" 2>/dev/null || true
done

if [ "${MODE}" = "build" ]; then
    rm -rf "${STAGING}${PREFIX}/libexec/install/portage/var/tmp" \
           "${STAGING}${PREFIX}/libexec/install/portage/var/cache" \
           2>/dev/null || true
fi

if [ "${VARIANT}" = "cli" ]; then
    rm -f "${STAGING}${PREFIX}/sbin/php-fpm" 2>/dev/null || true
    rm -rf "${STAGING}${PREFIX}/etc/php-fpm.d" "${STAGING}${PREFIX}/etc/php-fpm.conf" 2>/dev/null || true
    rm -f "${STAGING}${PREFIX}/etc/php/conf.d/opcache-production.ini" 2>/dev/null || true
    rm -f "${STAGING}${PREFIX}/etc/php/conf.d/docker-fpm.ini" 2>/dev/null || true
fi

if [ "${VARIANT}" = "fpm" ]; then
    rm -f "${STAGING}${PREFIX}/bin/phpdbg" 2>/dev/null || true
    if [ -x /usr/local/bin/fix-fpm-config.sh ]; then
        /usr/local/bin/fix-fpm-config.sh "${STAGING}${PREFIX}"
    fi
fi

if [ "${MODE}" = "runtime" ]; then
    purge_runtime_install_artifacts
    if [ -x /usr/local/bin/harden-runtime.sh ]; then
        /usr/local/bin/harden-runtime.sh "${STAGING}" "${PREFIX}"
    fi
fi

if [ "${MODE}" = "build" ]; then
    rm -f "${STAGING}${PREFIX}/etc/php/conf.d/hardening-production.ini" 2>/dev/null || true
fi

verify_staging_openssl

echo ">>> collect-runtime: ${#SEEN[@]} shared libraries, variant=${VARIANT}, mode=${MODE}"
du -sh "${STAGING}" | awk '{print ">>> staging size:", $1}'
