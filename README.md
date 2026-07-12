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

| `ARCH` | Platforma | Tag (multi-arch w registry) |
|--------|-----------|-----------------------------|
| `amd64` (domyślnie) | `linux/amd64` | `ghcr.io/lemric/gentoo-php/php:cli-8.5.8` |
| `arm64` | `linux/arm64` | ten sam tag — manifest wybiera architekturę |

```bash
make all          # zalecane: bake cli + fpm (ARCH=amd64 domyślnie)
make verify
docker buildx bake -f docker-bake.hcl all              # amd64
docker buildx bake -f docker-bake.hcl all --set ARCH=arm64
# CI: bake per arch → manifest job łączy w cli-8.5.8 / fpm-8.5.8
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
| `cli` | `php:cli-8.5.8` | **Produkcja** — minimalny scratch runtime, UID 82 |
| `fpm` | `php:fpm-8.5.8` | **Produkcja** — minimalny FPM scratch, UID 82 |
| `cli-build` | `php:cli-build-8.5.8` | Multi-stage helper — PIE, phpize, install-lib (nie deployuj) |
| `fpm-build` | `php:fpm-build-8.5.8` | Multi-stage helper dla FPM |

## Zgodność z docker-library/php

Interfejs identyczny:

- `docker-php-source`
- `docker-php-ext-configure`
- `docker-php-ext-install`
- `docker-php-ext-enable`
- `docker-php-pie-install` (alias: `docker-php-pecl-install`)
- `docker-php-env`
- `install-lib` (Gentoo atoms via bundled Portage; wymaga `USER root` w RUN)
- `docker-php-install-cleanup` (automatycznie po każdej instalacji)
- `docker-php-export-runtime` (eksport overlay do multi-stage)
- `docker-php-entrypoint` (identyczny skrypt jak w [docker-library/php](https://github.com/docker-library/php/blob/master/8.5/alpine3.24/cli/docker-php-entrypoint))

Bazowy zestaw rozszerzeń odpowiada świeżemu `php:8.5-cli` / `php:8.5-fpm`.  
Runtime ini (`proc_open`, `putenv`, `allow_url_fopen`, brak `open_basedir`) — **zgodność z docker-library** pod Symfony/Laravel.  
**Nie ma** gd, intl, zip, pdo_mysql — dokładasz je świadomie.

## Dokładanie rozszerzeń

### Opcja A — w `docker/Dockerfile` (zalecane produkcyjnie)

Odkomentuj sekcję w stage `builder-php`:

```dockerfile
RUN install-lib libjpeg libpng freetype \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd
```

### Opcja B — downstream Dockerfile (multi-stage, zalecane)

**`cli` / `fpm`** = minimalny runtime (bez gcc, emerge, phpize).  
**`cli-build` / `fpm-build`** = helper do instalacji rozszerzeń — używaj tylko jako stage pośredni.

```dockerfile
FROM ghcr.io/lemric/gentoo-php/php:cli-build-8.5.8 AS ext

RUN install-lib libjpeg libpng freetype \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-pie-install redis \
    && docker-php-export-runtime /export

FROM ghcr.io/lemric/gentoo-php/php:cli-8.5.8
COPY --from=ext /export/ /
USER www-data
```

Finalny obraz = **tylko** runtime + rozszerzenia (ldd closure). Install stack nie trafia do produkcji.

Rozszerzenia spoza core PHP: [PIE](https://github.com/php/pie) (`docker-php-pie-install`).  
Skróty PECL (`redis`, `xdebug`) mapują się przez [scripts/build/pie-package-map](scripts/build/pie-package-map).  
`docker-php-pecl-install` to symlink — stary interfejs działa.

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

### `cli` (produkcja — framework runtime + shell)

- `php` + ldd closure, statyczny **`/bin/sh`** + **`/usr/bin/env`** (busybox)
- **`/usr/bin/php`** → symlink — shebangi `#!/usr/bin/env php` i `#!/usr/bin/php`
- `docker-php-entrypoint` — jak w docker-library (`-f` → php)
- **Composer, artisan, queue** — `proc_open`, `putenv`, `pcntl`, `symlink` dostępne (jak official)
- **Brak** bash, gcc, emerge, phpize, PIE w runtime

### `fpm` (produkcja — hardened, bez shella)

- `php-fpm` + ldd closure — **zero** `/bin/sh`
- `hardening-production.ini` — bezpieczne domyślne prod (bez `disable_functions`; zgodność z docker-library)
- FPM: `security.limit_extensions = .php`, ping `/fpm-ping` — **bez** `open_basedir`
- Probes: `php /usr/local/libexec/php/docker-php-healthcheck.php`

Opcjonalny extra lockdown (Composer/queue/Process przestaną działać): skopiuj `configs/php/conf.d/hardening-strict.ini` do obrazu aplikacji.

### `cli-build` / `fpm-build` (tylko multi-stage)

- Wszystko z runtime + PIE, phpize, `install-lib`, Portage binpkg w `/usr/local/libexec/install`
- Po instalacji: `docker-php-export-runtime /export` → skopiuj do minimalnego `cli`/`fpm`

Każdy skrypt instalacji kończy się **obowiązkowym cleanup** (temp, cache, strip `.so`).

## Bezpieczeństwo

- Gentoo **hardened** profile (PIE, SSP, CET)
- **FULL RELRO** (`-Wl,-z,now`)
- **FORTIFY_SOURCE=3**
- Produkcja **CLI**: statyczny `/bin/sh` (busybox) — skrypty shell, **FPM**: bez shella
- **fail-closed** `harden-runtime.sh` + `verify-hardening.sh`
- Zawsze **USER 82:82** (www-data)
- FPM: **SIGQUIT**, `security.limit_extensions`
- **HEALTHCHECK** — PHP probes (bez sh)
- CI: multi-arch manifests, BuildKit cache

## Health probes (Docker / Kubernetes)

Wbudowany `/usr/local/libexec/php/docker-php-healthcheck.php` (PHP, bez shell):

| Probe | FPM | CLI |
|-------|-----|-----|
| `startup` | `php-fpm -t` (K8s) / sanity config | PHP ≥ 8.0 |
| `liveness` | PID file lub port `:9000` | always OK |
| `readiness` | FastCGI ping (`/fpm-ping` → `pong`) | core extensions |
| `health` | liveness + readiness | readiness |

```bash
# Shebang #!/usr/bin/env php (Symfony, Composer bin, itp.)
docker run --rm -v "$PWD:/app" -w /app \
  ghcr.io/lemric/gentoo-php/php:cli-8.5.8 ./bin/console

# Shell interaktywny / skrypt bash
docker run --rm -it ghcr.io/lemric/gentoo-php/php:cli-8.5.8 /bin/sh
docker run --rm ghcr.io/lemric/gentoo-php/php:cli-8.5.8 /bin/sh deploy.sh

# Healthcheck (exec, bez shella)
docker run --rm --entrypoint php ghcr.io/lemric/gentoo-php/php:cli-8.5.8 \
  /usr/local/libexec/php/docker-php-healthcheck.php health
```

FPM pool ma `ping.path = /fpm-ping` i `ping.response = pong` (konfigurowalne przez env).

Przykład Kubernetes: [examples/k8s/fpm-probes.yaml](examples/k8s/fpm-probes.yaml)

## Kubernetes

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 82
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop: ["ALL"]
volumeMounts:
  - name: tmp
    mountPath: /tmp
volumes:
  - name: tmp
    emptyDir: {}
```

## Różnice względem oficjalnego obrazu

| | Official | Gentoo Scratch |
|---|----------|----------------|
| Baza | Debian | scratch |
| FPM root | tak (setuid) | **nie** (zawsze www-data) |
| Shell | `/bin/sh` (dash) | **cli**: statyczny busybox; **fpm**: brak |
| Entrypoint | shell wrapper | **cli**: `docker-php-entrypoint`; **fpm**: `php-fpm` |
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
