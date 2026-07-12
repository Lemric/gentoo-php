#!/usr/bin/env bash
# gemato wrapper for ephemeral Docker builders.
#
# emerge-webrsync verifies snapshots with gemato openpgp-verify-detached, which
# refreshes keys from keyservers by default. Remote builders often block or
# misconfigure keyserver access ("No keyserver available").
#
# Stage3 already ships current Gentoo release keys in
# /usr/share/openpgp-keys/gentoo-release.asc — offline verification is enough
# for snapshot signature checks inside the build container.
set -euo pipefail

REAL_GEMATO="${GEMATO_REAL:-/usr/bin/gemato}"
if [[ ! -x "${REAL_GEMATO}" ]]; then
	REAL_GEMATO="$(command -v gemato)"
fi

if [[ "${1:-}" == "openpgp-verify-detached" ]]; then
	shift
	exec "${REAL_GEMATO}" openpgp-verify-detached --no-refresh-keys "$@"
fi

exec "${REAL_GEMATO}" "$@"
