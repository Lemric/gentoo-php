#!/usr/bin/env bash
# setup-fpm-config.sh — production FPM config (applied once on unified builder)
set -euo pipefail

cd /usr/local/etc

cp php-fpm.conf.default php-fpm.conf
cp php-fpm.d/www.conf.default php-fpm.d/www.conf

sed -i \
    -e 's/^user = .*/;user = www-data/' \
    -e 's/^group = .*/;group = www-data/' \
    -e 's/^;\?listen = 127.0.0.1:9000/listen = 9000/' \
    -e 's/^listen = .*/listen = 9000/' \
    -e 's/^;\?listen.owner.*/;listen.owner = unused/' \
    -e 's/^;\?listen.group.*/;listen.group = unused/' \
    php-fpm.d/www.conf

printf '%s\n' \
    '[global]' \
    'daemonize = no' \
    'error_log = /proc/self/fd/2' \
    'log_limit = 8192' \
    > php-fpm.d/zz-docker.conf

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
    >> php-fpm.d/zz-docker.conf
