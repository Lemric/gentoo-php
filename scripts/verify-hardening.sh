#!/usr/bin/env bash
# verify-hardening.sh — fail-closed checks on production runtime images
#
# Usage: verify-hardening.sh <image> [cli|fpm]
set -euo pipefail

IMAGE="${1:?image reference required}"
PROFILE="${2:-fpm}"

fail() { echo "HARDENING FAIL: $*" >&2; exit 1; }

echo ">>> verify-hardening: ${IMAGE} (profile=${PROFILE})"

if [ "${PROFILE}" = "cli" ]; then
    docker run --rm --entrypoint /bin/sh "${IMAGE}" -c '
        test -x /bin/sh && test -x /bin/busybox || exit 1
        test -x /usr/bin/env || exit 1
        test -x /usr/bin/wget || exit 1
        test -x /usr/bin/php || exit 1
        test -f /etc/services || exit 1
        grep -qE "^(http|https)[[:space:]]+[0-9]+" /etc/services
        /usr/bin/env php -v >/dev/null
        wget -q -O /dev/null -T 20 https://getcomposer.org/installer
        test -x /usr/local/bin/docker-php-entrypoint || exit 1
        echo "OK: /bin/sh + env/wget/php + /etc/services"
    ' || fail "CLI shell/env/wget/php"

    docker run --rm --entrypoint /usr/local/bin/php "${IMAGE}" -r '
        $forbidden = [
            "/usr/bin/emerge", "/usr/bin/gcc",
            "/usr/local/bin/pie", "/usr/local/bin/phpize",
            "/usr/local/libexec/install",
        ];
        foreach ($forbidden as $path) {
            if (file_exists($path)) {
                fwrite(STDERR, "forbidden: {$path}\n");
                exit(1);
            }
        }
        echo "OK: build tools absent\n";
    ' || fail "forbidden paths in CLI"
else
    docker run --rm --entrypoint /usr/local/bin/php "${IMAGE}" -r '
        $forbidden = [
            "/bin/sh", "/bin/busybox",
            "/usr/local/bin/docker-php-entrypoint",
            "/usr/bin/emerge", "/usr/bin/gcc",
            "/usr/local/bin/pie", "/usr/local/bin/phpize",
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
    ' || fail "forbidden paths in FPM"
fi

docker run --rm --entrypoint /usr/local/bin/php "${IMAGE}" -r '
if (!is_readable("/usr/local/libexec/php/docker-php-healthcheck.php")) {
    fwrite(STDERR, "missing PHP healthcheck\n");
    exit(1);
}
echo "OK: PHP healthcheck present\n";
' || fail "healthcheck missing"

echo ">>> verify-hardening: OK"
