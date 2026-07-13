#!/usr/bin/env bash
# install-shell-rootfs.sh — /bin/sh (busybox) + /bin/bash (Gentoo) into scratch rootfs
#
# Usage: install-shell-rootfs.sh <rootfs> [cli|fpm|build]
#
# cli/build — busybox sh + bash + /usr/bin/env + /usr/bin/wget + /usr/bin/php symlink
# fpm       — busybox sh + bash (docker-php-entrypoint parity)
set -euo pipefail

ROOTFS="${1:?rootfs path required}"
PROFILE="${2:-cli}"

case "${PROFILE}" in
    cli|fpm|build) ;;
    *)
        echo "install-shell-rootfs: profile must be cli, fpm, or build" >&2
        exit 1
        ;;
esac

declare -A SEEN

copy_into_rootfs() {
    local src="$1"
    local dst="${ROOTFS}${src}"
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

copy_elf_closure() {
    local src="$1"
    local resolved queue dep lib
    resolved="$(readlink -f "${src}" 2>/dev/null || echo "${src}")"
    copy_into_rootfs "${src}"
    queue=("${resolved}")
    while [ "${#queue[@]}" -gt 0 ]; do
        dep="${queue[0]}"
        queue=("${queue[@]:1}")
        [ -n "${dep}" ] || continue
        [ -n "${SEEN[$dep]:-}" ] && continue
        SEEN[$dep]=1
        copy_into_rootfs "${dep}"
        for lib in $(resolve_deps "${dep}"); do
            queue+=("${lib}")
        done
    done
}

install_busybox() {
    local bb
    emerge --verbose sys-apps/busybox
    bb="$(readlink -f "$(command -v busybox)")"
    mkdir -p "${ROOTFS}/bin"
    cp -L "${bb}" "${ROOTFS}/bin/busybox"
    strip --strip-all "${ROOTFS}/bin/busybox"
    ln -sf busybox "${ROOTFS}/bin/sh"
    file "${ROOTFS}/bin/busybox" | grep -qi 'statically linked'
}

install_bash() {
    local bash_bin
    emerge --verbose app-shells/bash
    bash_bin="$(readlink -f "$(command -v bash)")"
    copy_elf_closure "${bash_bin}"
    mkdir -p "${ROOTFS}/bin" "${ROOTFS}/usr/bin"
    if [ -x "${ROOTFS}/bin/bash" ]; then
        ln -sf ../bin/bash "${ROOTFS}/usr/bin/bash"
    elif [ -x "${ROOTFS}/usr/bin/bash" ]; then
        ln -sf ../usr/bin/bash "${ROOTFS}/bin/bash"
    else
        echo "install-shell-rootfs: bash missing under ${ROOTFS}" >&2
        exit 1
    fi
}

install_cli_extras() {
    mkdir -p "${ROOTFS}/usr/bin"
    ln -sf ../../bin/busybox "${ROOTFS}/usr/bin/env"
    ln -sf ../../bin/busybox "${ROOTFS}/usr/bin/wget"
    ln -sf ../local/bin/php "${ROOTFS}/usr/bin/php"
}

verify_rootfs() {
    local bash_bin interp
    test -x "${ROOTFS}/bin/sh"
    for candidate in "${ROOTFS}/bin/bash" "${ROOTFS}/usr/bin/bash"; do
        if [ -x "${candidate}" ]; then
            bash_bin="${candidate}"
            break
        fi
    done
    [ -n "${bash_bin}" ] || {
        echo "install-shell-rootfs: bash binary missing" >&2
        exit 1
    }
    file "${bash_bin}" | grep -qi 'ELF'
    interp="$(readelf -l "${bash_bin}" 2>/dev/null | awk '/interpreter/ {print $NF}' | tr -d '[]' || true)"
    if [ -n "${interp}" ] && [ ! -e "${ROOTFS}${interp}" ]; then
        echo "install-shell-rootfs: missing interpreter ${interp} in rootfs" >&2
        exit 1
    fi
    "${ROOTFS}/bin/sh" -c 'true'

    if [ "${PROFILE}" != "fpm" ]; then
        test -x "${ROOTFS}/usr/bin/env"
        test -x "${ROOTFS}/usr/bin/wget"
        grep -qE '^(http|https)[[:space:]]+[0-9]+' "${ROOTFS}/etc/services"
        "${ROOTFS}/bin/busybox" wget -q -O /dev/null -T 20 https://getcomposer.org/installer
    fi

    echo ">>> install-shell-rootfs: OK (${PROFILE})"
}

echo ">>> install-shell-rootfs: ${ROOTFS} profile=${PROFILE}"
install_busybox
install_bash

case "${PROFILE}" in
    cli|build) install_cli_extras ;;
esac

verify_rootfs
