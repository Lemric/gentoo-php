#!/usr/bin/env bash
# fix-fpm-config.sh — idempotent FPM config for scratch runtime
#
# Usage: fix-fpm-config.sh <install-prefix>
#   e.g. /usr/local  or  /staging/usr/local
#
# Fixes php/php-src#20845 (include=NONE/...) and log/pid paths removed by collect-runtime.
set -euo pipefail

PREFIX="${1:?install prefix required}"
ETC="${PREFIX}/etc"
FPM_D="${ETC}/php-fpm.d"

[ -d "${ETC}" ] || exit 0

if [ ! -f "${ETC}/php-fpm.conf" ] && [ -f "${ETC}/php-fpm.conf.default" ]; then
    cp "${ETC}/php-fpm.conf.default" "${ETC}/php-fpm.conf"
fi

if [ -d "${FPM_D}" ] && [ ! -f "${FPM_D}/www.conf" ] && [ -f "${FPM_D}/www.conf.default" ]; then
    cp "${FPM_D}/www.conf.default" "${FPM_D}/www.conf"
fi

[ -f "${ETC}/php-fpm.conf" ] || exit 0

sed -i \
    -e 's|^include=.*|include=/usr/local/etc/php-fpm.d/*.conf|' \
    -e 's|^;*error_log = .*|error_log = /proc/self/fd/2|' \
    -e 's|^;*pid = .*|pid = /tmp/php-fpm.pid|' \
    "${ETC}/php-fpm.conf"

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

mkdir -p "${FPM_D}"

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
    >> "${FPM_D}/zz-docker.conf"
