#!/bin/bash
# Unpack an ASUS/Merlin *.pkgtb (u-boot FIT) firmware image and emit a reproducible manifest.
# Usage: tools/pkgtb-unpack.sh <image.pkgtb> <outdir>
# Needs: u-boot-tools (dumpimage), squashfs-tools (unsquashfs). Optional: binwalk.
# Output: <outdir>/fit.txt, bootfs.bin, rootfs.sqsh, rootfs/, manifest.txt (path mode size sha256, sorted)
set -euo pipefail
IMG="${1:?image.pkgtb}"; OUT="${2:?outdir}"
command -v dumpimage >/dev/null || { echo "missing dumpimage (apt install u-boot-tools)"; exit 1; }
command -v unsquashfs >/dev/null || { echo "missing unsquashfs (apt install squashfs-tools)"; exit 1; }
mkdir -p "$OUT"; IMG="$(readlink -f "$IMG")"; cd "$OUT"
dumpimage -l "$IMG" > fit.txt
# sub-image index: 0 = bootfs (kernel+dtb bundle), 1 = nand_squashfs rootfs
dumpimage -T flat_dt -p 0 -o bootfs.bin "$IMG" >/dev/null
dumpimage -T flat_dt -p 1 -o rootfs.sqsh "$IMG" >/dev/null
rm -rf rootfs; unsquashfs -q -n -d rootfs rootfs.sqsh >/dev/null
# manifest: skip pseudo/dev entries, hash regular files, record symlink targets
( cd rootfs && find . -mindepth 1 \( -type f -o -type l -o -type d \) -printf '%p\t%y\t%m\t%s\t%l\n' | LC_ALL=C sort ) > manifest.tsv
( cd rootfs && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum ) > sha256.txt
sha256sum "$IMG" bootfs.bin rootfs.sqsh > image-hashes.txt
echo "unpacked: $(wc -l < manifest.tsv) entries, $(wc -l < sha256.txt) files -> $OUT"
