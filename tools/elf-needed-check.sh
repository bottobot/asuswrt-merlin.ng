#!/bin/bash
# List ELF files in an unpacked rootfs whose DT_NEEDED libraries are not present in it.
# Usage: tools/elf-needed-check.sh <rootfs_dir>   -> prints "path|missing_lib" lines (sorted)
# Needs: readelf (binutils). A library counts as present if any file or symlink with that
# basename exists under lib/, usr/lib/ (any depth) or the rootfs's other lib dirs.
set -uo pipefail
R="${1:?rootfs dir}"
cd "$R" || exit 2
export LC_ALL=C
find . \( -path './lib/*' -o -path './usr/lib/*' -o -path './usr/local/lib/*' -o -path './rom/*/lib/*' \) \
     \( -type f -o -type l \) -printf '%f\n' | sort -u > /tmp/elfcheck.libs.$$
find . -type f -perm /111 -o -type f -name '*.so*' | sort -u | while IFS= read -r f; do
  head -c 4 "$f" 2>/dev/null | grep -q $'\x7fELF' || continue
  readelf -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | while IFS= read -r lib; do
    grep -qxF "$lib" /tmp/elfcheck.libs.$$ || echo "${f#./}|$lib"
  done
done | sort -u
rm -f /tmp/elfcheck.libs.$$
