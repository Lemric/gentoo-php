#!/usr/bin/env bash
# fix-fpm-config.sh — idempotent FPM config for scratch runtime
#
# Usage: fix-fpm-config.sh <install-prefix>
#   e.g. /usr/local  or  /staging/usr/local
set -euo pipefail

PREFIX="${1:?install prefix required}"
ETC="${PREFIX}/etc"
FPM_D="${ETC}/php-fpm.d"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/php-fpm.conf"
[ -f "${TEMPLATE}" ] || TEMPLATE="/usr/local/share/gentoo-php/fpm/php-fpm.conf"

[ -d "${ETC}" ] || exit 0

mkdir -p "${FPM_D}"

if [ ! -f "${FPM_D}/www.conf" ] && [ -f "${FPM_D}/www.conf.default" ]; then
    cp "${FPM_D}/www.conf.default" "${FPM_D}/www.conf"
fi

install -m 644 "${TEMPLATE}" "${ETC}/php-fpm.conf"

if [ -f "${FPM_D}/www.conf" ]; then
    sed -i \
        -e 's/^user = .*/;user = www-data/' \
        -e 's/^group = .*/;group = www-data/' \
        -e 's/^;\?listen = 127.0.0.1:9000/listen = 9000/' \
        -e 's/^listen = .*/listen = 9000/' \
        -e 's/^;\?listen.owner.*/;listen.owner = unused/' \
        -e 's/^;\?listen.group.*/;listen.group = unused/' \
        "${FPM_D}/www.conf"
fi

printf '%s\n' \
    '[global]' \
    'daemonize = no' \
    'error_log = /proc/self/fd/2' \
    'log_limit = 8192' \
    > "${FPM_D}/zz-docker.conf"

printf '%s\n' \
    '[www]' \
    'pm = dynamic' \
    'pm.max_children = 50' \
    'pm.start_servers = 5' \
    'pm.min_spare_servers = 5' \
    'pm.max_spare_servers = 35' \
    'pm.max_requests = 500' \
    'pm.process_idle_timeout = 10s' \
    'access.log = /proc/self/fd/2' \
    'slowlog = /proc/self/fd/2' \
    'clear_env = no' \
    'catch_workers_output = yes' \
    'decorate_workers_output = no' \
    'request_terminate_timeout = 300s' \
    'ping.path = /fpm-ping' \
    'ping.response = pong' \
    'security.limit_extensions = .php' \
    'php_admin_flag[expose_php] = off' \
    'php_admin_flag[allow_url_fopen] = off' \
    'php_admin_flag[allow_url_include] = off' \
    'php_admin_value[open_basedir] = /var/www/html:/tmp' \
    >> "${FPM_D}/zz-docker.conf"

if grep -Fq 'NONE/' "${ETC}/php-fpm.conf"; then
    echo "fix-fpm-config: broken include still present in ${ETC}/php-fpm.conf" >&2
    exit 1
fi

if [ ! -f "${FPM_D}/www.conf" ] || [ ! -f "${FPM_D}/zz-docker.conf" ]; then
    echo "fix-fpm-config: missing pool configs under ${FPM_D}" >&2
    exit 1
fi
