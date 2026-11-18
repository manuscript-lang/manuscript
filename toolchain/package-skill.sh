#!/bin/sh
# Packs the agent skill that a built `ms` bundles into manuscript-skill.tar.gz and its checksum.
#
#   sh toolchain/package-skill.sh <path-to-ms> <output-directory>
#
# The archive holds one folder, `manuscript/`, stamped with that compiler's version. Every
# release attaches it under the same file name, so releases/latest/download/ is a stable URL.
set -eu

[ $# -eq 2 ] || { echo "usage: package-skill.sh <ms> <output-directory>" >&2; exit 2; }
ms="$1"
out="$2"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

"$ms" skill -o "$work"
mkdir -p "$out"
tar -C "$work" -czf "$out/manuscript-skill.tar.gz" manuscript
(cd "$out" && { sha256sum manuscript-skill.tar.gz 2>/dev/null || shasum -a 256 manuscript-skill.tar.gz; } >manuscript-skill.tar.gz.sha256)
