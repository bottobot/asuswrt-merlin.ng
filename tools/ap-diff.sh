#!/bin/sh
# ap-diff.sh <dirA> <dirB>
# POSIX sh. Diffs each *.txt section produced by ap-baseline.sh. Lines starting '#V ' (volatile) are ignored.
# Output: '== <section>' per section, then diff body ('<' = A, '>' = B). Last line: result=identical|differs sections_differing=N
# Exit: 0 identical, 1 differences, 2 usage/error.
set -u
if [ $# -ne 2 ] || [ ! -d "$1" ] || [ ! -d "$2" ]; then
  echo "usage: ap-diff.sh <dirA> <dirB>" >&2
  exit 2
fi
A=$1
B=$2
T=${TMPDIR:-/tmp}/ap-diff.$$
mkdir -p "$T" || exit 2
trap 'rm -rf "$T"' EXIT INT TERM

{ ls "$A"; ls "$B"; } 2>/dev/null | grep '\.txt$' | sort -u > "$T/names"
n=0
while read -r f; do
  echo "== ${f%.txt}"
  if [ ! -f "$A/$f" ]; then echo "only-in-B: $f"; n=$((n + 1)); continue; fi
  if [ ! -f "$B/$f" ]; then echo "only-in-A: $f"; n=$((n + 1)); continue; fi
  grep -v '^#V ' "$A/$f" > "$T/a"
  grep -v '^#V ' "$B/$f" > "$T/b"
  if ! diff -u "$T/a" "$T/b" > "$T/d"; then
    sed '1,2d' "$T/d"
    n=$((n + 1))
  fi
done < "$T/names"

if [ "$n" -eq 0 ]; then echo "result=identical sections_differing=0"; exit 0; fi
echo "result=differs sections_differing=$n"
exit 1
