#!/usr/bin/env bash
# setup-fpm-config.sh — production FPM config (applied once on unified builder)
set -euo pipefail

cd /usr/local/etc
cp php-fpm.d/www.conf.default php-fpm.d/www.conf
exec /usr/local/bin/fix-fpm-config.sh /usr/local
