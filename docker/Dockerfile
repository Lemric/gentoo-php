# syntax=docker/dockerfile:1.7
#
# Gentoo PHP 8.5 — unified build pipeline
#
# ONE PHP compile (builder-php) → variant split at collect-cli / collect-fpm only.
# Build (default linux/amd64):
#   make cli
#   make cli ARCH=arm64
#   docker build --platform linux/amd64 --target cli ...
#
# Pipeline:
#   builder-base → toolchain → php-builder → builder-php
#     ├─ collect-cli  → cli
#     ├─ collect-fpm  → fpm
#     └─ extension-sdk
#   scratch-runtime (shared rootfs layer)
# =============================================================================

ARG PHP_VERSION=8.5.8
ARG PHP_GPG_KEYS=""
ARG PHP_SHA256=""
ARG GENTOO_STAGE3=gentoo/stage3:nomultilib
ARG NONROOT_UID=82
ARG NONROOT_GID=82
ARG NONROOT_USER=www-data
# Parallel build tuning (0 = auto-detect from nproc at build time)
ARG BUILD_JOBS=0
ARG EMERGE_JOBS=0
ARG BUILD_LOAD=0
# tmpfs for Portage compile temp (bytes); 32G fits 128GB RAM builders
ARG PORTAGE_TMPFS_SIZE=34359738368
# BuildKit cache scope (amd64 / arm64) — persists in buildx builder storage on docker-builder
ARG GENTOO_CACHE_ID=amd64
# 1 = force emerge-webrsync on every builder-base rebuild; 0 = sync only if tree missing
ARG GENTOO_SYNC=0

# -----------------------------------------------------------------------------
# builder-base
# -----------------------------------------------------------------------------
FROM ${GENTOO_STAGE3} AS builder-base

ARG TARGETARCH
ARG BUILD_JOBS
ARG EMERGE_JOBS
ARG BUILD_LOAD
ARG PORTAGE_TMPFS_SIZE
ARG GENTOO_CACHE_ID
ARG GENTOO_SYNC

COPY portage/make.conf /etc/portage/make.conf
COPY portage/make.conf.d/ /etc/portage/make.conf.d/
COPY portage/make.conf.amd64 portage/make.conf.arm64 /tmp/portage-arch/
RUN ARCH="${TARGETARCH:-$(uname -m)}" \
    && case "${ARCH}" in x86_64) ARCH=amd64;; aarch64) ARCH=arm64;; esac \
    && cat "/tmp/portage-arch/make.conf.${ARCH}" >> /etc/portage/make.conf \
    && rm -rf /tmp/portage-arch

COPY portage/package.use/ /etc/portage/package.use/
COPY portage/package.env/ /etc/portage/package.env/
COPY portage/env/ /etc/portage/env/
COPY portage/sets/ /etc/portage/sets/
COPY portage/gnupg/dirmngr.conf /etc/gnupg/dirmngr.conf
COPY scripts/build/portage-tune.sh /usr/local/bin/portage-tune.sh
COPY scripts/build/gemato-docker-wrapper.sh /usr/local/bin/gemato
RUN chmod +x /usr/local/bin/portage-tune.sh /usr/local/bin/gemato \
    && BUILD_JOBS="${BUILD_JOBS}" EMERGE_JOBS="${EMERGE_JOBS}" BUILD_LOAD="${BUILD_LOAD}" \
       portage-tune.sh

ENV PATH="/usr/local/bin:${PATH}"

RUN if [ ! -d /var/db/repos/gentoo/profiles ]; then \
        echo '>>> portage tree missing — emerge-webrsync (required for stage3)'; \
        emerge-webrsync; \
    elif [ "${GENTOO_SYNC}" = "1" ]; then \
        echo '>>> GENTOO_SYNC=1 — emerge-webrsync'; \
        emerge-webrsync; \
    else \
        echo '>>> reuse portage tree from cached layer (GENTOO_SYNC=0)'; \
    fi \
    && ARCH="${TARGETARCH:-$(uname -m)}" \
    && case "${ARCH}" in \
         x86_64|amd64) eselect profile set default/linux/amd64/23.0/hardened || true ;; \
         aarch64|arm64) eselect profile set default/linux/arm64/23.0/hardened || true ;; \
         *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
       esac \
    && eselect profile show

# stage3 already satisfies @system; skip @world (would recompile hundreds of atoms every layer invalidation)
# toolchain — build tools + PHP build deps in ONE emerge (single layer)
# -----------------------------------------------------------------------------
FROM builder-base AS toolchain

ARG BUILD_JOBS
ARG EMERGE_JOBS
ARG BUILD_LOAD
ARG PORTAGE_TMPFS_SIZE
ARG GENTOO_CACHE_ID
ARG GENTOO_SYNC

RUN --mount=type=cache,target=/var/cache/distfiles,id=gentoo-distfiles-${GENTOO_CACHE_ID},sharing=locked \
    --mount=type=cache,target=/var/cache/binhost,id=gentoo-binhost-${GENTOO_CACHE_ID},sharing=locked \
    --mount=type=cache,target=/var/cache/ccache,id=gentoo-ccache-${GENTOO_CACHE_ID},sharing=locked \
    --mount=type=tmpfs,target=/var/tmp/portage,size=${PORTAGE_TMPFS_SIZE} \
    mkdir -p /var/tmp/portage /var/cache/binhost \
    && export PORTAGE_TMPDIR=/var/tmp/portage \
    && emerge --verbose @php-toolchain @php-build-deps \
    && BUILD_JOBS="${BUILD_JOBS:-0}" EMERGE_JOBS="${EMERGE_JOBS:-0}" BUILD_LOAD="${BUILD_LOAD:-0}" \
       portage-tune.sh

COPY scripts/entrypoint/docker-php-entrypoint /usr/local/bin/docker-php-entrypoint
RUN chmod 755 /usr/local/bin/docker-php-entrypoint

# -----------------------------------------------------------------------------
# php-builder — verified source + docker-php-* tooling
# -----------------------------------------------------------------------------
FROM toolchain AS php-builder

ARG PHP_VERSION
ARG PHP_GPG_KEYS
ARG PHP_SHA256
ARG BUILD_JOBS
ARG GENTOO_CACHE_ID

COPY scripts/docker-php-source /usr/local/bin/docker-php-source
COPY scripts/docker-php-ext-configure /usr/local/bin/docker-php-ext-configure
COPY scripts/docker-php-ext-install /usr/local/bin/docker-php-ext-install
COPY scripts/docker-php-ext-enable /usr/local/bin/docker-php-ext-enable
COPY scripts/docker-php-pecl-install /usr/local/bin/docker-php-pecl-install
COPY scripts/docker-php-env /usr/local/bin/docker-php-env
COPY scripts/build/install-lib /usr/local/bin/install-lib
COPY scripts/build/configure-php.sh /usr/local/bin/configure-php.sh
COPY scripts/build/fix-fpm-config.sh /usr/local/bin/fix-fpm-config.sh
COPY scripts/build/setup-fpm-config.sh /usr/local/bin/setup-fpm-config.sh
COPY scripts/build/verify-php-tarball.sh /usr/local/bin/verify-php-tarball.sh
RUN chmod +x /usr/local/bin/docker-php-* /usr/local/bin/install-lib \
              /usr/local/bin/configure-php.sh /usr/local/bin/fix-fpm-config.sh \
              /usr/local/bin/setup-fpm-config.sh \
              /usr/local/bin/verify-php-tarball.sh

WORKDIR /usr/src

RUN --mount=type=cache,target=/root/.gnupg,sharing=locked \
    GNUPGHOME=/root/.gnupg \
    PHP_VERSION="${PHP_VERSION}" \
    PHP_GPG_KEYS="${PHP_GPG_KEYS}" \
    PHP_SHA256="${PHP_SHA256}" \
    verify-php-tarball.sh

ENV PHP_SRC_TARBALL=/usr/src/php.tar.xz \
    PHP_SRC_DIR=/usr/src/php \
    PHP_INI_DIR=/usr/local/etc/php

RUN docker-php-source extract

# -----------------------------------------------------------------------------
# builder-php — SINGLE configure + compile (CLI + FPM + phpdbg superset)
# Extension hooks go HERE (before collect-*), not in duplicate builds.
# -----------------------------------------------------------------------------
FROM php-builder AS builder-php

ARG BUILD_JOBS
ARG GENTOO_CACHE_ID
ENV BUILD_JOBS=${BUILD_JOBS}

# Optional extensions — uncomment once:
# RUN install-lib libjpeg libpng freetype \
#     && docker-php-ext-configure gd --with-freetype --with-jpeg \
#     && docker-php-ext-install -j"$(nproc)" gd

RUN --mount=type=cache,target=/var/cache/ccache,id=gentoo-ccache-${GENTOO_CACHE_ID},sharing=locked \
    --mount=type=tmpfs,target=/tmp/php-build,size=8589934592 \
    configure-php.sh \
    && setup-fpm-config.sh

COPY configs/php/conf.d/opcache-production.ini /usr/local/etc/php/conf.d/
COPY configs/php/conf.d/docker-fpm.ini /usr/local/etc/php/conf.d/

# -----------------------------------------------------------------------------
# extension-sdk — same unified build, optional PECL
# -----------------------------------------------------------------------------
FROM builder-php AS extension-sdk
ARG GENTOO_CACHE_ID
RUN --mount=type=cache,target=/var/cache/distfiles,id=gentoo-distfiles-${GENTOO_CACHE_ID},sharing=locked \
    --mount=type=cache,target=/var/cache/binhost,id=gentoo-binhost-${GENTOO_CACHE_ID},sharing=locked \
    --mount=type=cache,target=/var/cache/ccache,id=gentoo-ccache-${GENTOO_CACHE_ID},sharing=locked \
    mkdir -p /var/cache/binhost \
    emerge --verbose dev-php/pecl 2>/dev/null \
    || emerge --verbose app-archives/pecl-php 2>/dev/null \
    || true

# -----------------------------------------------------------------------------
# collect-cli / collect-fpm — ONLY divergence point (prune, no recompile)
# Both fork from builder-php; BuildKit runs them in parallel after builder-php.
# -----------------------------------------------------------------------------
FROM builder-php AS collect-cli
COPY scripts/build/collect-runtime.sh scripts/build/analyze-deps.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/collect-runtime.sh /usr/local/bin/analyze-deps.sh
RUN mkdir -p /staging/usr/local \
    && cp -a /usr/local/. /staging/usr/local/ \
    && collect-runtime.sh /staging /usr/local cli \
    && analyze-deps.sh /staging /usr/local

FROM builder-php AS collect-fpm
COPY scripts/build/collect-runtime.sh scripts/build/analyze-deps.sh scripts/build/fix-fpm-config.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/collect-runtime.sh /usr/local/bin/analyze-deps.sh /usr/local/bin/fix-fpm-config.sh
RUN mkdir -p /staging/usr/local \
    && cp -a /usr/local/. /staging/usr/local/ \
    && collect-runtime.sh /staging /usr/local fpm \
    && analyze-deps.sh /staging /usr/local

# -----------------------------------------------------------------------------
# scratch-runtime — shared rootfs skeleton (+ /bin/sh via static busybox)
# -----------------------------------------------------------------------------
FROM builder-base AS scratch-runtime
ARG NONROOT_UID
ARG NONROOT_GID
ARG NONROOT_USER
ARG INCLUDE_TZDATA=1
ARG PORTAGE_TMPFS_SIZE
ARG GENTOO_CACHE_ID
ARG GENTOO_SYNC

RUN mkdir -p /rootfs/etc /rootfs/tmp /rootfs/usr/local/bin /rootfs/var/www/html \
    && printf '%s:x:%s:%s:%s:/var/www/html:/sbin/nologin\n' \
        "${NONROOT_USER}" "${NONROOT_UID}" "${NONROOT_GID}" "${NONROOT_USER}" \
        > /rootfs/etc/passwd \
    && printf '%s:x:%s:\n' "${NONROOT_USER}" "${NONROOT_GID}" > /rootfs/etc/group \
    && printf 'hosts: files dns\n' > /rootfs/etc/nsswitch.conf \
    && chmod 1777 /rootfs/tmp \
    && chown -R "${NONROOT_UID}:${NONROOT_GID}" /rootfs/var/www/html \
    && cp -a /etc/ssl /rootfs/etc/ssl \
    && cp -a /etc/pki /rootfs/etc/pki 2>/dev/null || true

RUN if [ "${INCLUDE_TZDATA}" = "1" ]; then \
        mkdir -p /rootfs/usr/share \
        && cp -a /usr/share/zoneinfo /rootfs/usr/share/zoneinfo \
        && echo 'UTC' > /rootfs/etc/timezone; \
    fi

COPY --from=toolchain /usr/local/bin/docker-php-entrypoint /rootfs/usr/local/bin/docker-php-entrypoint

RUN --mount=type=cache,target=/var/cache/distfiles,id=gentoo-distfiles-${GENTOO_CACHE_ID},sharing=locked \
    --mount=type=cache,target=/var/cache/binhost,id=gentoo-binhost-${GENTOO_CACHE_ID},sharing=locked \
    --mount=type=cache,target=/var/cache/ccache,id=gentoo-ccache-${GENTOO_CACHE_ID},sharing=locked \
    --mount=type=tmpfs,target=/var/tmp/portage,size=${PORTAGE_TMPFS_SIZE} \
    mkdir -p /var/tmp/portage /var/cache/binhost \
    && export PORTAGE_TMPDIR=/var/tmp/portage \
    && emerge --verbose sys-apps/busybox \
    && BB="$(readlink -f "$(command -v busybox)")" \
    && mkdir -p /rootfs/bin \
    && cp -L "${BB}" /rootfs/bin/busybox \
    && strip --strip-all /rootfs/bin/busybox \
    && ln -sf busybox /rootfs/bin/sh \
    && file /rootfs/bin/busybox | grep -qi 'statically linked' \
    && chmod 755 /rootfs/usr/local/bin/docker-php-entrypoint \
    && head -n1 /rootfs/usr/local/bin/docker-php-entrypoint | grep -q '^#!/bin/sh$' \
    && /rootfs/bin/sh -c 'echo busybox-sh-ok'

# -----------------------------------------------------------------------------
# cli / fpm — FROM scratch (shared scratch-runtime + variant collect)
# -----------------------------------------------------------------------------
FROM scratch AS cli
ARG NONROOT_UID
ARG NONROOT_GID
ARG PHP_VERSION

LABEL org.opencontainers.image.title="gentoo-php-cli" \
      org.opencontainers.image.version="${PHP_VERSION}" \
      org.opencontainers.image.base.name="scratch"

COPY --from=scratch-runtime /rootfs/ /
COPY --from=collect-cli /staging/ /

ENV PHP_INI_DIR=/usr/local/etc/php \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/bin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /var/www/html
USER ${NONROOT_UID}:${NONROOT_GID}

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/docker-php-entrypoint", "php", "-r", "exit(0);"]

ENTRYPOINT ["/usr/local/bin/docker-php-entrypoint"]
CMD ["php", "-a"]

FROM scratch AS fpm
ARG NONROOT_UID
ARG NONROOT_GID
ARG PHP_VERSION

LABEL org.opencontainers.image.title="gentoo-php-fpm" \
      org.opencontainers.image.version="${PHP_VERSION}" \
      org.opencontainers.image.base.name="scratch"

COPY --from=scratch-runtime /rootfs/ /
COPY --from=collect-fpm /staging/ /

ENV PHP_INI_DIR=/usr/local/etc/php \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/bin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /var/www/html
EXPOSE 9000
USER ${NONROOT_UID}:${NONROOT_GID}

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["/usr/local/bin/docker-php-entrypoint", "php-fpm", "-t"]

ENTRYPOINT ["/usr/local/bin/docker-php-entrypoint"]
CMD ["php-fpm"]
