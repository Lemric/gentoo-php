#!/usr/bin/env bash
# merge-install-root.sh — copy runtime libs from ephemeral emerge --root into live /
set -euo pipefail

SRC="${1:?source root required}"
DEST="${2:-/}"

copy_tree() {
    local rel="$1"
    [ -d "${SRC}${rel}" ] || return 0
    mkdir -p "${DEST}${rel}"
    cp -a "${SRC}${rel}/." "${DEST}${rel}/"
}

for rel in usr/lib64 usr/lib lib64 lib etc; do
    copy_tree "/${rel}"
done

if [ -d "${SRC}/usr/local" ]; then
    mkdir -p "${DEST}/usr/local"
    cp -a "${SRC}/usr/local/." "${DEST}/usr/local/"
fi
