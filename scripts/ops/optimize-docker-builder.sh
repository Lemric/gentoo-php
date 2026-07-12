#!/usr/bin/env bash
# optimize-docker-builder.sh — tune Docker/BuildKit on the build host (32c / 128GB)
#
# Run ON the build server (e.g. ssh docker-builder):
#   curl -fsSL ... | sudo bash
#   sudo ./scripts/ops/optimize-docker-builder.sh
#
# Idempotent; backs up /etc/docker/daemon.json before changes.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
	exec sudo bash "$0" "$@"
fi

log() { printf '>>> %s\n' "$*"; }

BUILDKIT_TOML="/etc/buildkit/buildkitd.toml"
DAEMON_JSON="/etc/docker/daemon.json"
SYSCTL_DROPIN="/etc/sysctl.d/99-docker-build.conf"
CACHE_ROOT="/var/cache/gentoo-docker"
BUILDER_NAME="gentoo-fast"

log "Installing QEMU user-static + binfmt for linux/arm64 builds"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq qemu-user-static binfmt-support jq

log "Registering binfmt handlers (tonistiigi/binfmt)"
docker run --privileged --rm tonistiigi/binfmt --install all

log "Writing ${BUILDKIT_TOML}"
mkdir -p /etc/buildkit
cat > "${BUILDKIT_TOML}" <<'EOF'
# BuildKit — 32 CPU / 128 GiB RAM build host (gentoo-php)
debug = false

insecure-entitlements = [ "security.insecure" ]

[worker.oci]
  enabled = true
  platforms = ["linux/amd64", "linux/arm64"]
  max-parallelism = 32
  gc = true
  reservedSpace = 21474836480
  maxUsedSpace = 128849018880
  minFreeSpace = 32212254720

[worker.containerd]
  enabled = false
EOF

if [ -f "${DAEMON_JSON}" ]; then
	cp -a "${DAEMON_JSON}" "${DAEMON_JSON}.bak.$(date +%Y%m%d%H%M%S)"
fi

log "Merging builder GC settings into ${DAEMON_JSON}"
if [ -f "${DAEMON_JSON}" ]; then
	jq '. + {
	  "builder": {
	    "config": "/etc/buildkit/buildkitd.toml",
	    "gc": {
	      "enabled": true,
	      "defaultKeepStorage": "120GB"
	    }
	  }
	}' "${DAEMON_JSON}" > "${DAEMON_JSON}.new"
else
	cat > "${DAEMON_JSON}.new" <<'EOF'
{
  "features": { "buildkit": true },
  "storage-driver": "overlay2",
  "builder": {
    "config": "/etc/buildkit/buildkitd.toml",
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "120GB"
    }
  }
}
EOF
fi
mv "${DAEMON_JSON}.new" "${DAEMON_JSON}"

log "Writing ${SYSCTL_DROPIN}"
cat > "${SYSCTL_DROPIN}" <<'EOF'
# Compile / BuildKit tuning (32c, 128G RAM, HDD-backed rootfs)
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 1048576
EOF
sysctl -p "${SYSCTL_DROPIN}" >/dev/null 2>&1 || true

log "Persistent Gentoo build caches: ${CACHE_ROOT}"
install -d -m 1777 "${CACHE_ROOT}"/distfiles "${CACHE_ROOT}"/binhost \
	"${CACHE_ROOT}"/ccache-amd64 "${CACHE_ROOT}"/ccache-arm64

log "Removing stale user buildx CLI override (v0.12 shadowing system plugin)"
for user_home in /home/ubuntu /root; do
	[ -d "${user_home}/.docker/cli-plugins" ] || continue
	if [ -f "${user_home}/.docker/cli-plugins/docker-buildx" ]; then
		rm -f "${user_home}/.docker/cli-plugins/docker-buildx"
		log "  removed ${user_home}/.docker/cli-plugins/docker-buildx"
	fi
done

log "Restarting Docker (live-restore keeps running containers)"
systemctl restart docker
sleep 3

log "Creating Buildx builder: ${BUILDER_NAME}"
docker buildx rm -f "${BUILDER_NAME}" 2>/dev/null || true
docker buildx create \
	--name "${BUILDER_NAME}" \
	--driver docker-container \
	--driver-opt network=host \
	--driver-opt "image=moby/buildkit:latest" \
	--buildkitd-flags "--allow-insecure-entitlement=network.host" \
	--config "${BUILDKIT_TOML}" \
	--platform linux/amd64,linux/arm64 \
	--use \
	--bootstrap

docker buildx install 2>/dev/null || true

log "Verification"
docker buildx version
docker buildx ls
docker buildx inspect "${BUILDER_NAME}" | head -25
update-binfmts --display | grep -E 'qemu-aarch64|aarch64' || true
echo
log "Done. Default builder: ${BUILDER_NAME}"
log "Cache dirs: ${CACHE_ROOT}/{distfiles,binhost,ccache-amd64,ccache-arm64}"
log "Note: root disk is HDD RAID1 — tmpfs in Dockerfile is important for emerge I/O."
