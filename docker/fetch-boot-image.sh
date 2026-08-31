#!/bin/sh
# Downloads the official OpenWrt x86-64 combined image and produces a clean,
# bootable raw disk at docker/boot-image/boot.img.
#
# Why this script exists instead of just pointing docker-compose at the
# upstream URL directly: the official .img.gz has benign trailing bytes
# after its valid gzip stream (confirmed: `gzip -dc` still produces a
# complete, correct disk image — the trailing bytes just make gzip's
# strict integrity check exit non-zero as a warning, not real corruption).
# Some extractors (including the one used by an earlier candidate in this
# project's history) treat that warning as fatal. Pre-decompressing once,
# here, sidesteps that entirely — see
# docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md
# for the full investigation.
set -e

VERSION="23.05.5"
URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/openwrt-${VERSION}-x86-64-generic-ext4-combined.img.gz"
OUT_DIR="$(cd "$(dirname "$0")" && pwd)/boot-image"
OUT_IMG="${OUT_DIR}/boot.img"

mkdir -p "${OUT_DIR}"

if [ -f "${OUT_IMG}" ]; then
  echo "boot.img already exists at ${OUT_IMG} — delete it first to re-fetch."
  exit 0
fi

echo "Downloading OpenWrt ${VERSION} x86-64 combined image..."
curl -sL -o "${OUT_DIR}/openwrt.img.gz" "${URL}"

echo "Decompressing (a 'trailing garbage ignored' warning here is expected and harmless — see comment above)..."
gzip -dc "${OUT_DIR}/openwrt.img.gz" > "${OUT_IMG}" || true

if [ ! -s "${OUT_IMG}" ]; then
  echo "ERROR: decompression produced an empty or missing file." >&2
  exit 1
fi

file "${OUT_IMG}" | grep -qi "boot sector" || {
  echo "ERROR: ${OUT_IMG} doesn't look like a valid disk image (expected a boot sector)." >&2
  exit 1
}

rm -f "${OUT_DIR}/openwrt.img.gz"
echo "OK: ${OUT_IMG} ready ($(du -h "${OUT_IMG}" | cut -f1))."
