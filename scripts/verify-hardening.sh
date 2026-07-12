#!/usr/bin/env bash
# verify-hardening.sh — fail-closed checks on production runtime image
set -euo pipefail

IMAGE="${1:?image reference required}"

fail() { echo "HARDENING FAIL: $*" >&2; exit 1; }

echo ">>> verify-hardening: ${IMAGE}"

docker run --rm --entrypoint /usr/local/bin/php "${IMAGE}" -r '
$forbidden = [
    "/bin/sh", "/bin/busybox", "/usr/bin/emerge", "/usr/bin/gcc",
    "/usr/local/bin/pie", "/usr/local/bin/phpize",
    "/usr/local/bin/docker-php-entrypoint",
    "/usr/local/libexec/install",
];
foreach ($forbidden as $path) {
    if (file_exists($path)) {
        fwrite(STDERR, "forbidden: {$path}\n");
        exit(1);
    }
}
if (is_dir("/bin") && count(scandir("/bin")) > 2) {
    fwrite(STDERR, "forbidden: /bin is populated\n");
    exit(1);
}
echo "OK: forbidden paths absent\n";
' || fail "forbidden paths present"

docker run --rm --entrypoint /usr/local/bin/php "${IMAGE}" -r '
if (!is_readable("/usr/local/libexec/php/docker-php-healthcheck.php")) {
    fwrite(STDERR, "missing PHP healthcheck\n");
    exit(1);
}
echo "OK: PHP healthcheck present\n";
' || fail "healthcheck missing"

echo ">>> verify-hardening: OK"
