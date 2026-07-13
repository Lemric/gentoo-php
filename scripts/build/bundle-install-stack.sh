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
    make libtoolize libtool pkg-config
    re2c bison flex sed awk grep find
    python-exec2c emerge
)

for name in "${TOOL_BINS[@]}"; do
    path="$(command -v "${name}" 2>/dev/null || true)"
    [ -n "${path}" ] && copy_with_ldd "${path}"
done

# autoconf/automake share + real binaries (phpize needs autoheader, not just ac-wrapper)
for share in /usr/share/autoconf /usr/share/autoconf-* /usr/share/aclocal /usr/share/aclocal-* /usr/share/automake-*; do
    [ -e "${share}" ] || continue
    mkdir -p "${DEST}$(dirname "${share}")"
    cp -a "${share}" "${DEST}${share}"
done

for tool in autoconf autoheader autom4te aclocal automake; do
    path="$(command -v "${tool}" 2>/dev/null || true)"
    [ -n "${path}" ] && copy_with_ldd "${path}"
done

# python-exec dispatch tree (emerge shebang: #!/usr/bin/python-exec2c)
if [ -d /usr/lib/python-exec ]; then
    mkdir -p "${DEST}/usr/lib"
    cp -a /usr/lib/python-exec "${DEST}/usr/lib/"
fi

# Real CPython + stdlib (command -v python3 is the python-exec wrapper, not the interpreter)
PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
REAL_PY="/usr/bin/python${PYVER}"
if [ ! -x "${REAL_PY}" ]; then
    REAL_PY="$(readlink -f "/usr/lib/python-exec/python${PYVER}/python" 2>/dev/null || true)"
fi
if [ -n "${REAL_PY}" ] && [ -x "${REAL_PY}" ]; then
    copy_with_ldd "${REAL_PY}"
else
    echo "bundle-install-stack: CPython ${PYVER} not found" >&2
    exit 1
fi

for pyroot in "/usr/lib/python${PYVER}" "/usr/lib64/python${PYVER}"; do
    [ -d "${pyroot}" ] || continue
    mkdir -p "${DEST}${pyroot}"
    cp -a "${pyroot}/." "${DEST}${pyroot}/"
done

# emerge / python-exec2c shebangs expect /usr/bin/python-exec2c
mkdir -p "${DEST}/usr/bin"
if [ ! -e "${DEST}/usr/bin/python-exec2c" ]; then
    ln -sf "../sbin/python-exec2c" "${DEST}/usr/bin/python-exec2c"
fi

cp -a /etc/portage/. "${PORTAGE}/etc/portage/"
[ -d /var/db/repos/gentoo ] && cp -a /var/db/repos/gentoo "${PORTAGE}/var/db/repos/gentoo"

# Binhost cache seed (may be empty; getbinpkg uses PKGDIR)
[ -d /var/cache/binhost ] && cp -a /var/cache/binhost/. "${DEST}/var/cache/binhost/" 2>/dev/null || true

echo ">>> bundle-install-stack: ${DEST} ($(du -sh "${DEST}" | awk '{print $1}'))"
