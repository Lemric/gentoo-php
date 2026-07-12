#!/usr/bin/env bash
# verify-build.sh — end-to-end build verification
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="${ROOT}/docker/Dockerfile"
ARCH="${ARCH:-amd64}"
PLATFORM="${PLATFORM:-linux/${ARCH}}"
PHP_VERSION="${PHP_VERSION:-8.5.8}"
TAG_SUFFIX=""
[ "${ARCH}" != "amd64" ] && TAG_SUFFIX="-${ARCH}"
IMG_CLI="php:${PHP_VERSION}-cli${TAG_SUFFIX}"
IMG_FPM="php:${PHP_VERSION}-fpm${TAG_SUFFIX}"
ENTRYPOINT="/usr/local/bin/docker-php-entrypoint"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m!!! %s\033[0m\n' "$1"; exit 1; }

case "${ARCH}" in
    amd64|arm64) ;;
    *) fail "Unsupported ARCH=${ARCH} (use amd64 or arm64)" ;;
esac

step "0/8  PHP GPG keys (ARCH=${ARCH}, PLATFORM=${PLATFORM})"
if [ -n "${PHP_GPG_KEYS:-}" ]; then
	echo "Using PHP_GPG_KEYS from environment"
else
	echo "PHP_GPG_KEYS unset — verify-php-tarball.sh will use defaults and fetch keys via HTTPS"
fi

step "1/8  Build CLI (docker/Dockerfile → cli)"
DOCKER_BUILDKIT=1 docker build \
    --platform "${PLATFORM}" \
    -f "${DOCKERFILE}" \
    --target cli \
    --build-arg PHP_VERSION="${PHP_VERSION}" \
    --build-arg PHP_GPG_KEYS="${PHP_GPG_KEYS}" \
    --progress=plain \
    -t "${IMG_CLI}" "${ROOT}"

step "2/8  Build FPM"
DOCKER_BUILDKIT=1 docker build \
    --platform "${PLATFORM}" \
    -f "${DOCKERFILE}" \
    --target fpm \
    --build-arg PHP_VERSION="${PHP_VERSION}" \
    --build-arg PHP_GPG_KEYS="${PHP_GPG_KEYS}" \
    --progress=plain \
    -t "${IMG_FPM}" "${ROOT}"

step "3/8  Image sizes"
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E "${PHP_VERSION}-cli|${PHP_VERSION}-fpm|REPOSITORY"

step "4/8  Smoke tests"
docker run --rm "${IMG_CLI}" php -v
docker run --rm --entrypoint "${ENTRYPOINT}" "${IMG_FPM}" php-fpm -v

step "5/8  Base extensions + nonroot"
docker run --rm "${IMG_CLI}" php -r 'echo "PHP " . PHP_VERSION . PHP_EOL;'
for ext in curl mbstring openssl pdo_sqlite sqlite3 sodium ftp; do
    docker run --rm "${IMG_CLI}" php -m | grep -qi "^${ext}$" && echo "  [OK] ${ext}" || echo "  [MISS] ${ext}"
done

CLI_UID=$(docker run --rm "${IMG_CLI}" php -r 'echo posix_getuid();')
[ "${CLI_UID}" != "0" ] || fail "CLI runs as root"
echo "  [OK] CLI UID=${CLI_UID}"

step "6/8  FPM nonroot"
FPM_CID=$(docker run -d "${IMG_FPM}")
sleep 2
FPM_UID=$(docker top "${FPM_CID}" -o uid 2>/dev/null | tail -n +2 | tr -d ' ' | sort -u)
docker stop "${FPM_CID}" >/dev/null
docker rm "${FPM_CID}" >/dev/null
echo "${FPM_UID}" | grep -qE '^(0|root)$' && fail "FPM master runs as root" || echo "  [OK] FPM UID=${FPM_UID}"

step "7/8  Scratch surface check"
docker run --rm "${IMG_CLI}" /bin/sh -c 'echo "  [OK] /bin/sh works"'
docker run --rm --entrypoint "${ENTRYPOINT}" "${IMG_CLI}" php -r '
$bad = ["/bin/bash","/usr/bin/emerge","/usr/bin/gcc"];
foreach ($bad as $p) if (file_exists($p)) { echo "FOUND: $p\n"; exit(1); }
if (!is_executable("/bin/sh")) { echo "MISSING: /bin/sh\n"; exit(1); }
echo "OK: /bin/sh present, no bash/compiler/package-manager\n";
'

step "8/8  Optional security scans"
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
