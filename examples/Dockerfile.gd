# syntax=docker/dockerfile:1.7
#
# Extension build example — compile GD in cli-build, ship minimal runtime on cli
#
# Prerequisites:
#   make cli cli-build
#   docker build -f examples/Dockerfile.gd -t my/php:8.5-cli-gd .
#
# For production without extra extensions, use cli/fpm directly.
# For extensions baked into your app image, use cli-build/fpm-build multi-stage (see README).

ARG CLI_IMAGE=ghcr.io/lemric/gentoo-php/php:cli-8.5.8
ARG CLI_BUILD_IMAGE=ghcr.io/lemric/gentoo-php/php:cli-build-8.5.8
ARG NONROOT_UID=82
ARG NONROOT_GID=82

FROM ${CLI_BUILD_IMAGE} AS gd-builder

RUN install-lib libjpeg libpng freetype \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd \
    && php -m | grep -i gd \
    && docker-php-export-runtime /export

FROM ${CLI_IMAGE}

COPY --from=gd-builder /export/ /

WORKDIR /var/www/html
USER ${NONROOT_UID}:${NONROOT_GID}

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/php", "-r", "if (!extension_loaded('gd')) exit(1);"]

ENTRYPOINT ["/usr/local/bin/php"]
CMD ["-a"]
