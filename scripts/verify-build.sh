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
docker run --rm --entrypoint /bin/sh "${IMG_CLI}" -c '
    php -v >/dev/null && echo "  [OK] /bin/sh + php"
    printf "%s\n" "#!/usr/bin/env php" "<?php echo \"env-shebang-ok\\n\";" > /tmp/t.php
    chmod +x /tmp/t.php && /tmp/t.php | grep -q env-shebang-ok && echo "  [OK] #!/usr/bin/env php"
'
docker run --rm "${IMG_FPM}" php-fpm -t
docker run --rm --entrypoint /usr/local/bin/php "${IMG_FPM}" "${HEALTHCHECK}" readiness

step "6/9  Base extensions + HTTPS + framework runtime (CLI/FPM)"
docker run --rm "${IMG_CLI}" -r 'echo OPENSSL_VERSION_TEXT, PHP_EOL;'
framework_check='
function ok($cond, $msg) {
    if (!$cond) { fwrite(STDERR, "framework: {$msg}\n"); exit(1); }
}
ok(ini_get("allow_url_fopen"), "allow_url_fopen");
ok(!ini_get("allow_url_include"), "allow_url_include off");
ok(function_exists("proc_open"), "proc_open");
ok(function_exists("putenv"), "putenv");
ok(function_exists("symlink"), "symlink");
ok(function_exists("pcntl_signal"), "pcntl_signal");
$disabled = array_map("trim", explode(",", (string) ini_get("disable_functions")));
ok(!in_array("proc_open", $disabled, true), "proc_open not disabled");
ok(!in_array("putenv", $disabled, true), "putenv not disabled");
echo "  [OK] framework runtime parity\n";
'
docker run --rm "${IMG_CLI}" -r "${framework_check}"
docker run --rm "${IMG_CLI}" -r '
    ini_set("display_errors", "stderr");
    $ca = ini_get("openssl.cafile");
    if ($ca === "" || !is_readable($ca)) { fwrite(STDERR, "bad openssl.cafile\n"); exit(1); }
    $ctx = stream_context_create(["ssl" => ["verify_peer" => true, "verify_peer_name" => true]]);
    $fp = @fopen("https://getcomposer.org/", "r", false, $ctx);
    if ($fp === false) { fwrite(STDERR, "HTTPS failed\n"); exit(1); }
    fclose($fp);
    echo "  [OK] CLI HTTPS (openssl.cafile={$ca})\n";
'
docker run --rm --entrypoint /usr/local/bin/php "${IMG_FPM}" -r "${framework_check}"
docker run --rm --entrypoint /usr/local/bin/php "${IMG_FPM}" -r '
    ini_set("display_errors", "stderr");
    if (!ini_get("allow_url_fopen")) { fwrite(STDERR, "FPM allow_url_fopen disabled\n"); exit(1); }
    if (!extension_loaded("curl")) { fwrite(STDERR, "curl missing\n"); exit(1); }
    $ca = ini_get("openssl.cafile");
    if ($ca === "" || !is_readable($ca)) { fwrite(STDERR, "bad openssl.cafile\n"); exit(1); }
    $ch = curl_init("https://getcomposer.org/");
    curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_NOBODY => true, CURLOPT_TIMEOUT => 20]);
    curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($code < 200 || $code >= 400) { fwrite(STDERR, "FPM HTTPS curl failed HTTP {$code}\n"); exit(1); }
    echo "  [OK] FPM HTTPS curl (openssl.cafile={$ca})\n";
'
for ext in curl mbstring openssl pdo_sqlite sqlite3 sodium ftp; do
    docker run --rm "${IMG_CLI}" -m | grep -qi "^${ext}$" && echo "  [OK] ${ext}" || echo "  [MISS] ${ext}"
done
docker run --rm "${IMG_CLI}" -r '
    if (extension_loaded("Zend OPcache")) { fwrite(STDERR, "CLI OPcache should be off in base\n"); exit(1); }
    echo "  [OK] CLI OPcache off (official parity)\n";
'
docker run --rm --entrypoint /usr/local/bin/php "${IMG_FPM}" -r '
    if (extension_loaded("Zend OPcache")) { fwrite(STDERR, "FPM OPcache should be off in base\n"); exit(1); }
    echo "  [OK] FPM OPcache off (official parity)\n";
'

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
