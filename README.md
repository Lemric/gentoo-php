# Gentoo PHP 8.5 — Scratch Images

Produkcyjna alternatywa dla [docker-library/php](https://github.com/docker-library/php), zbudowana na **Gentoo Hardened**, dostarczana jako **`FROM scratch`**, zawsze **nonroot**.

## Priorytety

1. Bezpieczeństwo
2. Minimalny rozmiar
3. Wydajność
4. Zgodność z docker-library/php
5. Rozszerzalność

## Szybki start

```bash
export PHP_GPG_KEYS="<fingerprinty z https://www.php.net/downloads.php>"

# Domyślnie linux/amd64 (nawet na Mac Apple Silicon)
make cli

# Inna architektura
make cli ARCH=arm64
make all ARCH=arm64

# Bezpośrednio przez Docker
docker build --platform linux/amd64 -f docker/Dockerfile --target cli ...
docker build --platform linux/arm64 -f docker/Dockerfile --target cli ...
```

| `ARCH` | Platforma | Przykładowy tag |
|--------|-----------|-----------------|
| `amd64` (domyślnie) | `linux/amd64` | `php:8.5.8-cli` |
| `arm64` | `linux/arm64` | `php:8.5.8-cli-arm64` |

```bash
make all          # zalecane: bake cli + fpm (ARCH=amd64 domyślnie)
make verify
docker buildx bake -f docker-bake.hcl all              # amd64
docker buildx bake -f docker-bake.hcl all --set ARCH=arm64
docker buildx bake -f docker-bake.hcl multiarch        # obie architektury (CI)
```

## Architektura

```
builder-base → toolchain → php-builder → builder-php
    → collect-cli / collect-fpm → scratch-runtime → cli / fpm
```

Szczegóły: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Obrazy

| Target | Tag | Opis |
|--------|-----|------|
| `cli` | `php:8.5.8-cli` | PHP CLI, scratch, UID 82 |
| `fpm` | `php:8.5.8-fpm` | PHP-FPM, scratch, UID 82 |
| `extension-sdk` | `php:8.5.8-sdk` | Budowanie rozszerzeń (phpize, pecl) |

## Zgodność z docker-library/php

Interfejs identyczny:

- `docker-php-source`
- `docker-php-ext-configure`
- `docker-php-ext-install`
- `docker-php-ext-enable`
- `docker-php-pecl-install`
- `docker-php-env`
- `docker-php-entrypoint` (identyczny skrypt jak w [docker-library/php](https://github.com/docker-library/php/blob/master/8.5/alpine3.24/cli/docker-php-entrypoint))

Bazowy zestaw rozszerzeń odpowiada świeżemu `php:8.5-cli` / `php:8.5-fpm`.
**Nie ma** gd, intl, zip, pdo_mysql — dokładasz je świadomie.

## Dokładanie rozszerzeń

### Opcja A — w `docker/Dockerfile` (zalecane produkcyjnie)

Odkomentuj sekcję w stage `builder-php`:

```dockerfile
RUN install-lib libjpeg libpng freetype \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd
```

### Opcja B — downstream Dockerfile

```bash
make sdk
```

```dockerfile
FROM php:8.5.8-sdk
RUN install-lib libjpeg libpng freetype
RUN docker-php-ext-configure gd --with-freetype --with-jpeg
RUN docker-php-ext-install -j$(nproc) gd
```

Przykład: [examples/Dockerfile.gd](examples/Dockerfile.gd)

### Mapa pakietów

| Rozszerzenie | install-lib |
|---|---|
| gd | `libjpeg libpng freetype` |
| intl | `icu` |
| zip | `libzip` |
| pdo_pgsql | `libpq` |
| gmp | `gmp` |

Pełna mapa: [scripts/build/install-lib](scripts/build/install-lib)

## Scratch — co jest w obrazie

**Tylko:**
- `php` / `php-fpm`
- wymagane `.so` (ldd closure)
- CA certificates
- `/etc/passwd`, `/etc/group`, `nsswitch.conf`
- opcjonalnie `tzdata`
- `php.ini` templates + `conf.d/`
- `/bin/sh` (statyczny busybox) + `docker-php-entrypoint` (skrypt shell)

**Nigdy:**
- bash, gcc, emerge, apt, nagłówki, dokumentacja, locale cache

## Bezpieczeństwo

- Gentoo **hardened** profile (PIE, SSP, CET)
- **FULL RELRO** (`-Wl,-z,now`)
- **FORTIFY_SOURCE=3**
- **ThinLTO** + `-O3` + `-march=x86-64-v3` (amd64)
- Zawsze **USER 82:82** (www-data)
- FPM: **SIGQUIT** graceful shutdown
- **HEALTHCHECK** wbudowany
- CI: SBOM, provenance, cosign (tagi)

## Kubernetes

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 82
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

## Różnice względem oficjalnego obrazu

| | Official | Gentoo Scratch |
|---|----------|----------------|
| Baza | Debian | scratch |
| FPM root | tak (setuid) | **nie** (zawsze www-data) |
| Shell | `/bin/sh` (dash) | `/bin/sh` (statyczny busybox) |
| Optymalizacja | `-O2` | `-O3` + ThinLTO + `-march` |

## Struktura projektu

```
docker/Dockerfile       # Pipeline (wszystkie stage)
docker-bake.hcl         # Multi-arch CI
portage/                # make.conf, USE, package.env
scripts/                # docker-php-*, collect-runtime, install-lib
configs/                # FPM, opcache
docs/ARCHITECTURE.md    # Decyzje architektoniczne
Makefile                # Lokalne targety
```

## Aktualizacja PHP

1. Zmień `PHP_VERSION` w `Makefile` / `docker-bake.hcl`
2. Pobierz nowe `PHP_GPG_KEYS` z php.net
3. Opcjonalnie ustaw `PHP_SHA256`
4. `make verify`

## Licencja

PHP sources: [PHP License v3.01](https://www.php.net/license/). Build scripts: MIT.
