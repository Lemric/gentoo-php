#!/usr/bin/env bash
# verify-build.sh — end-to-end build verification
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="${ROOT}/docker/Dockerfile"
ARCH="${ARCH:-amd64}"
PLATFORM="${PLATFORM:-linux/${ARCH}}"
PHP_VERSION="${PHP_VERSION:-8.5.8}"
IMG_CLI="php:cli-${PHP_VERSION}"
IMG_FPM="php:fpm-${PHP_VERSION}"
HEALTHCHECK="/usr/local/libexec/php/docker-php-healthcheck.php"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m!!! %s\033[0m\n' "$1"; exit 1; }

case "${ARCH}" in
    amd64|arm64) ;;
    *) fail "Unsupported ARCH=${ARCH} (use amd64 or arm64)" ;;
esac

step "0/9  PHP GPG keys (ARCH=${ARCH}, PLATFORM=${PLATFORM})"
if [ -n "${PHP_GPG_KEYS:-}" ]; then
	echo "Using PHP_GPG_KEYS from environment"
else
	echo "PHP_GPG_KEYS unset — verify-php-tarball.sh will use defaults and fetch keys via HTTPS"
fi

step "1/9  Build CLI (docker/Dockerfile → cli)"
DOCKER_BUILDKIT=1 docker build \
    --platform "${PLATFORM}" \
    -f "${DOCKERFILE}" \
    --target cli \
    --build-arg PHP_VERSION="${PHP_VERSION}" \
    --build-arg PHP_GPG_KEYS="${PHP_GPG_KEYS}" \
    --progress=plain \
    -t "${IMG_CLI}" "${ROOT}"

step "2/9  Build FPM"
DOCKER_BUILDKIT=1 docker build \
    --platform "${PLATFORM}" \
    -f "${DOCKERFILE}" \
    --target fpm \
    --build-arg PHP_VERSION="${PHP_VERSION}" \
    --build-arg PHP_GPG_KEYS="${PHP_GPG_KEYS}" \
    --progress=plain \
    -t "${IMG_FPM}" "${ROOT}"

step "3/9  Image sizes"
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E "cli-${PHP_VERSION}|fpm-${PHP_VERSION}|REPOSITORY"

step "4/9  Smoke tests"
docker run --rm "${IMG_CLI}" -v
docker run --rm "${IMG_FPM}" -v
docker run --rm "${IMG_FPM}" -t

step "5/9  Health probes + CLI shell"
docker run --rm --entrypoint /usr/local/bin/php "${IMG_CLI}" "${HEALTHCHECK}" health
docker run --rm --entrypoint /bin/sh "${IMG_CLI}" -c 'php -v >/dev/null && echo "  [OK] /bin/sh + php"'
docker run --rm "${IMG_FPM}" /usr/local/sbin/php-fpm -t
docker run --rm --entrypoint /usr/local/bin/php "${IMG_FPM}" "${HEALTHCHECK}" readiness

step "6/9  Base extensions + nonroot"
docker run --rm "${IMG_CLI}" -r 'echo OPENSSL_VERSION_TEXT, PHP_EOL;'
for ext in curl mbstring openssl pdo_sqlite sqlite3 sodium ftp; do
    docker run --rm "${IMG_CLI}" -m | grep -qi "^${ext}$" && echo "  [OK] ${ext}" || echo "  [MISS] ${ext}"
done

CLI_UID=$(docker run --rm "${IMG_CLI}" -r 'echo posix_getuid();')
[ "${CLI_UID}" != "0" ] || fail "CLI runs as root"
echo "  [OK] CLI UID=${CLI_UID}"

step "7/9  FPM nonroot"
FPM_CID=$(docker run -d "${IMG_FPM}")
sleep 2
FPM_UID=$(docker top "${FPM_CID}" -o uid 2>/dev/null | tail -n +2 | tr -d ' ' | sort -u)
docker stop "${FPM_CID}" >/dev/null
docker rm "${FPM_CID}" >/dev/null
echo "${FPM_UID}" | grep -qE '^(0|root)$' && fail "FPM master runs as root" || echo "  [OK] FPM UID=${FPM_UID}"

step "8/9  Hardening verification"
"${ROOT}/scripts/verify-hardening.sh" "${IMG_CLI}" cli
"${ROOT}/scripts/verify-hardening.sh" "${IMG_FPM}" fpm

step "9/9  Optional security scans"
if command -v checksec >/dev/null 2>&1; then
    CID=$(docker create "${IMG_CLI}")
    docker cp "${CID}:/usr/local/bin/php" /tmp/php-extracted
    docker rm "${CID}" >/dev/null
    checksec --file=/tmp/php-extracted
    rm -f /tmp/php-extracted
else
    echo "checksec not installed — skipped"
fi

step "Done: ${IMG_CLI}, ${IMG_FPM} (${ARCH})"
