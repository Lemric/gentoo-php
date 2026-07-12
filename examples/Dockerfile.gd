# syntax=docker/dockerfile:1.7
#
# Extension build example — compile GD in SDK, ship minimal runtime on cli base
#
# Prerequisites:
#   make sdk
#   docker build -f examples/Dockerfile.gd -t my/php:8.5-cli-gd .
#
# For production, prefer adding the gd-builder RUN block to docker/Dockerfile
# in stage builder-php (Option A — recommended).

ARG SDK_IMAGE=php:8.5.8-sdk
ARG CLI_IMAGE=php:8.5.8-cli
ARG NONROOT_UID=82
ARG NONROOT_GID=82

FROM ${SDK_IMAGE} AS gd-builder

RUN install-lib libjpeg libpng freetype \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd \
    && docker-php-ext-enable gd \
    && php -m | grep -i gd

# ldd closure for gd.so + deps → minimal overlay on scratch cli
RUN mkdir -p /staging \
    && cp -a /usr/local/. /staging/usr/local/ \
    && collect-runtime.sh /staging /usr/local cli \
    && analyze-deps.sh /staging /usr/local

FROM ${CLI_IMAGE}

COPY --from=gd-builder /staging/ /

WORKDIR /var/www/html
USER ${NONROOT_UID}:${NONROOT_GID}

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/docker-php-entrypoint", "php", "-r", "if (!extension_loaded('gd')) exit(1);"]

ENTRYPOINT ["/usr/local/bin/docker-php-entrypoint"]
CMD ["php", "-a"]
