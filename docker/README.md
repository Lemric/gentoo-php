# Pipeline Stage Map

**Unified build:** PHP is compiled exactly once in `builder-php`.  
CLI and FPM differ only at `collect-cli` / `collect-fpm` (prune, no recompile).

```bash
make all          # recommended: bake cli + fpm in one go (shared layers)
make cli          # single target (uses BuildKit cache from prior all)
```

| Stage | Responsibility |
|-------|----------------|
| `builder-base` | Portage sync (if needed), hardened profile, portage config |
| `toolchain` | GCC + all build deps (one emerge) + `docker-php-entrypoint` |
| `php-builder` | PHP source verify, docker-php-* scripts |
| `builder-php` | **Single** configure + compile (CLI+FPM+phpdbg superset) |
| `collect-cli` / `collect-fpm` | ldd closure, harden-runtime (profile cli/fpm) |
| `collect-cli-build` / `collect-fpm-build` | + install stack (build mode) |
| `cli` / `fpm` | FROM scratch production runtime |
| `cli-build` / `fpm-build` | multi-stage extension helpers |
| `scratch-runtime` | passwd, CA, `/tmp` — **FPM** skeleton (no shell) |
| `scratch-runtime-cli` | + `/bin/sh`, `/bin/bash`, entrypoint — **CLI** |
| `scratch-runtime` | + `/bin/sh`, `/bin/bash`, entrypoint — **FPM** |
| `scratch-runtime-build` | shells + entrypoint — `*-build` helpers |

BuildKit graph after `builder-php`:

```
builder-php ─┬─ collect-cli ──────── cli
             ├─ collect-cli-build ─ cli-build
             ├─ collect-fpm ──────── fpm
             └─ collect-fpm-build ─ fpm-build
```

Both collect stages run in parallel; PHP is never compiled twice.

## Build host (docker-builder)

Optimized for **32 CPU / 128 GB RAM** (`v4.brandoriented.io`):

| Component | Setting |
|-----------|---------|
| Buildx builder | `gentoo-fast` (BuildKit on docker-builder, max-parallelism=32) |
| Platforms | `linux/amd64` native, `linux/arm64` via QEMU/binfmt |
| Cache (BuildKit) | `id=gentoo-distfiles-{arch}`, `gentoo-binhost-{arch}`, `gentoo-ccache-{arch}` |
| Binpkg reuse | `getbinpkg` + `buildpkg` in same builder (do not `buildx rm gentoo-fast`) |

From Mac (context `remote-builder`):

```bash
make setup-cache-dirs       # once: persistent cache dirs on docker-builder
make setup-builder          # verify/create gentoo-fast buildx
make cli-fast               # 1st run compiles; 2nd reuses binhost cache
make cli ARCH=arm64         # arm64 via QEMU (slower than native amd64)
```

Re-run server tuning after OS upgrade:

```bash
ssh docker-builder 'sudo bash -s' < scripts/ops/optimize-docker-builder.sh
```

**Note:** Binhost/distfiles/ccache persist in the **gentoo-fast** BuildKit cache. Do not run `docker buildx rm gentoo-fast` or `docker builder prune` if you want getbinpkg reuse. Keep `GENTOO_SYNC=0` (default).

**Note:** build host rootfs is **HDD RAID1** (not NVMe) — Portage tmpfs in `docker/Dockerfile` is important for emerge I/O.

