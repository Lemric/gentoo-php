#!/usr/bin/env bash
# bundle-install-stack.sh — minimal Portage + build toolchain for cli/fpm installs
#
# Usage: bundle-install-stack.sh [dest=/usr/local/libexec/install]
set -euo pipefail

DEST="${1:-/usr/local/libexec/install}"
BIN="${DEST}/bin"
PORTAGE="${DEST}/portage"

mkdir -p "${BIN}" "${PORTAGE}/etc/portage" "${PORTAGE}/var/db/repos" "${DEST}/var/cache/binhost"

copy_with_ldd() {
    local bin="$1"
    local queue dep seen=()
    [ -x "${bin}" ] || return 0
    queue=("${bin}")
    while [ "${#queue[@]}" -gt 0 ]; do
        dep="${queue[0]}"
        queue=("${queue[@]:1}")
        case " ${seen[*]} " in *" ${dep} "*) continue ;; esac
        seen+=("${dep}")
        mkdir -p "${DEST}$(dirname "${dep}")"
        cp -aL "${dep}" "${DEST}${dep}"
        while IFS= read -r lib; do
            [ -n "${lib}" ] || continue
            queue+=("${lib}")
        done < <(ldd "${dep}" 2>/dev/null | awk '/=>/ { if ($3 ~ /^\//) print $3; next } /^\// { print $1 }')
    done
}

TOOL_BINS=(
    git unzip tar xz bzip2 gzip
    gcc g++ cpp cc c++ ld
    make autoconf automake libtoolize libtool pkg-config
    re2c bison flex sed awk grep find
    python3 emerge
)

for name in "${TOOL_BINS[@]}"; do
    path="$(command -v "${name}" 2>/dev/null || true)"
    [ -n "${path}" ] && copy_with_ldd "${path}"
done

# Portage Python modules + config (binpkg-only installs at runtime)
PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
for pyroot in "/usr/lib/python${PYVER}" "/usr/lib64/python${PYVER}"; do
    [ -d "${pyroot}/site-packages/portage" ] || continue
    mkdir -p "${DEST}${pyroot}/site-packages"
    cp -a "${pyroot}/site-packages/portage" "${DEST}${pyroot}/site-packages/"
done

cp -a /etc/portage/. "${PORTAGE}/etc/portage/"
[ -d /var/db/repos/gentoo ] && cp -a /var/db/repos/gentoo "${PORTAGE}/var/db/repos/gentoo"

# Binhost cache seed (may be empty; getbinpkg uses PKGDIR)
[ -d /var/cache/binhost ] && cp -a /var/cache/binhost/. "${DEST}/var/cache/binhost/" 2>/dev/null || true

echo ">>> bundle-install-stack: ${DEST} ($(du -sh "${DEST}" | awk '{print $1}'))"
