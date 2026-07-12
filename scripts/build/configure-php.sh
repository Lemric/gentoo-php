#!/usr/bin/env bash
# configure-php.sh — single unified PHP configure+build (CLI + FPM superset)
# One compile; collect-runtime.sh prunes variant-specific artifacts later.
set -euo pipefail

cd /usr/src/php
mkdir -p "${PHP_INI_DIR}/conf.d"

eval "$(docker-php-env)"

./buildconf --force
./configure \
    --build="$(gcc -dumpmachine)" \
    --with-config-file-path="${PHP_INI_DIR}" \
    --with-config-file-scan-dir="${PHP_INI_DIR}/conf.d" \
    --enable-option-checking=fatal \
    --with-mhash \
    --with-pic \
    --enable-mbstring \
    --enable-mysqlnd \
    --with-password-argon2 \
    --with-sodium=shared \
    --with-pdo-sqlite=/usr \
    --with-sqlite3=/usr \
    --with-curl \
    --with-iconv \
    --with-openssl \
    --with-readline \
    --with-zlib \
    --enable-phpdbg \
    --enable-phpdbg-readline \
    --enable-embed \
    --with-pear \
    --disable-cgi \
    --enable-fpm \
    --with-fpm-user=www-data \
    --with-fpm-group=www-data

if [ "${BUILD_JOBS:-0}" = "0" ] || [ "${BUILD_JOBS:-0}" -lt 1 ] 2>/dev/null; then
    MAKE_JOBS="$(nproc)"
else
    MAKE_JOBS="${BUILD_JOBS}"
fi
make -j"${MAKE_JOBS}"
make install

find /usr/local -type f -perm '/0111' -exec strip --strip-all {} + 2>/dev/null || true
cp php.ini-development php.ini-production "${PHP_INI_DIR}/"
docker-php-ext-enable sodium

php --version
php-fpm --version
