#!/usr/bin/env bash
# Download and GPG-verify PHP source tarball (docker-library/php compatible).
# Fetches release keys over HTTPS (no dirmngr / gpg --recv-keys).
set -euo pipefail

# Same defaults as docker-library/php 8.5 — override via PHP_GPG_KEYS if php.net adds signers.
DEFAULT_PHP_GPG_KEYS="1198C0117593497A5EC5C199286AF1F9897469DC 49D9AF6BC72A80D6691719C8AA23F5BE9C7097D4 D95C03BC702BE9515344AE3374E44BC9067701A5"

if [ -z "${PHP_VERSION:-}" ]; then
	echo 'ERROR: PHP_VERSION is required' >&2
	exit 1
fi

PHP_GPG_KEYS="${PHP_GPG_KEYS:-${DEFAULT_PHP_GPG_KEYS}}"

fetch_and_import_key() {
	local fp="${1}"
	local tmp

	fp="${fp// /}"
	fp="$(printf '%s' "${fp}" | tr '[:lower:]' '[:upper:]')"

	if gpg --batch --list-keys "${fp}" >/dev/null 2>&1; then
		return 0
	fi

	echo ">>> fetching GPG key ${fp} (keys.openpgp.org)"
	tmp="$(mktemp)"
	if curl -fsSL --retry 3 --retry-delay 2 \
		"https://keys.openpgp.org/vks/v1/by-fingerprint/${fp}" \
		-o "${tmp}" \
		&& gpg --batch --import "${tmp}" 2>/dev/null \
		&& gpg --batch --list-keys "${fp}" >/dev/null 2>&1; then
		rm -f "${tmp}"
		return 0
	fi
	rm -f "${tmp}"

	echo ">>> fetching GPG key ${fp} (keyserver.ubuntu.com)"
	tmp="$(mktemp)"
	if curl -fsSL --retry 3 --retry-delay 2 \
		"https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${fp: -8}" \
		-o "${tmp}" \
		&& gpg --batch --import "${tmp}" 2>/dev/null \
		&& gpg --batch --list-keys "${fp}" >/dev/null 2>&1; then
		rm -f "${tmp}"
		return 0
	fi
	rm -f "${tmp}"

	echo "ERROR: could not fetch GPG key ${fp}" >&2
	echo 'Set PHP_GPG_KEYS from https://www.php.net/downloads.php' >&2
	return 1
}

cd "${PHP_SRC_DIR:-/usr/src}"

curl -fsSL -o php.tar.xz "https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz"
curl -fsSL -o php.tar.xz.asc "https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz.asc"

if [ -n "${PHP_SHA256:-}" ]; then
	echo "${PHP_SHA256} php.tar.xz" | sha256sum -c -
fi

if [ -z "${GNUPGHOME:-}" ]; then
	GNUPGHOME="$(mktemp -d)"
	export GNUPGHOME
	chmod 700 "${GNUPGHOME}"
	cleanup_gnupg=1
else
	mkdir -p "${GNUPGHOME}"
	chmod 700 "${GNUPGHOME}"
	cleanup_gnupg=0
fi

for key in ${PHP_GPG_KEYS}; do
	fetch_and_import_key "${key}"
done

gpg --batch --verify php.tar.xz.asc php.tar.xz

if [ "${cleanup_gnupg}" -eq 1 ]; then
	rm -rf "${GNUPGHOME}"
fi

echo ">>> PHP ${PHP_VERSION} source verified (GPG)"
