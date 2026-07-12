#!/usr/bin/env bash
# ensure-ca-bundle.sh — guarantee PEM bundle path for PHP/openssl in scratch rootfs
set -euo pipefail

ROOT="${1:?rootfs path required}"
BUNDLE="${ROOT}/etc/ssl/certs/ca-certificates.crt"

[ -d "${ROOT}/etc/ssl/certs" ] || {
    echo "ensure-ca-bundle: missing ${ROOT}/etc/ssl/certs" >&2
    exit 1
}

if [ -s "${BUNDLE}" ]; then
    echo ">>> ensure-ca-bundle: ${BUNDLE} ($(
        wc -c < "${BUNDLE}" | tr -d ' '
    ) bytes)"
    exit 0
fi

for candidate in \
    "${ROOT}/etc/ssl/certs/ca-certificates.pem" \
    "${ROOT}/etc/ssl/cert.pem" \
    "${ROOT}/etc/ssl/certs.pem"; do
    if [ -s "${candidate}" ]; then
        cp -a "${candidate}" "${BUNDLE}"
        echo ">>> ensure-ca-bundle: ${BUNDLE} (from ${candidate})"
        exit 0
    fi
done

tmp="$(mktemp)"
find "${ROOT}/etc/ssl/certs" -maxdepth 1 -type f \
    ! -name 'ca-certificates.crt' \
    \( -name '*.pem' -o -name '*.0' \) -print0 2>/dev/null \
    | sort -z | xargs -0 cat > "${tmp}" 2>/dev/null || true

if [ ! -s "${tmp}" ]; then
    echo "ensure-ca-bundle: no CA material under ${ROOT}/etc/ssl/certs" >&2
    exit 1
fi

install -m 644 "${tmp}" "${BUNDLE}"
rm -f "${tmp}"
echo ">>> ensure-ca-bundle: ${BUNDLE} (concatenated, $(wc -c < "${BUNDLE}" | tr -d ' ') bytes)"
