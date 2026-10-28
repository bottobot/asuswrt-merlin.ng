#!/bin/bash
# Compare two unpacked images (output dirs of tools/pkgtb-unpack.sh).
# Usage: tools/pkgtb-compare.sh <dirA> <dirB>
# Prints: files only in A, only in B, files whose content differs. Exit 0 always (report tool).
set -uo pipefail
A="${1:?dirA}"; B="${2:?dirB}"
echo "== only in A"; comm -23 <(cut -f1 "$A/manifest.tsv") <(cut -f1 "$B/manifest.tsv")
echo "== only in B"; comm -13 <(cut -f1 "$A/manifest.tsv") <(cut -f1 "$B/manifest.tsv")
echo "== content differs"; comm -3 <(sort "$A/sha256.txt") <(sort "$B/sha256.txt") | awk '{print $2}' | sort -u
echo "== metadata differs (mode/size/linktarget)"; comm -3 "$A/manifest.tsv" "$B/manifest.tsv" | cut -f1 | sort -u
