# Task 2 report: baseline CI 3006.102.9 vs official

Done with a concern. Commit `985f9b054d` "docs: baseline diff of CI 3006.102.9 build vs official image" adds `docs/baseline-3006.102.9-ci-vs-official.md` (172 lines, markdown only; no CI triggered). No source files modified, no images committed.

Inputs
- CI: `gh run download 40640600800 -R bottobot/asuswrt-merlin.ng -n gt-ax6000-9c96e1f8426de963d6db28400437f8827c0862c7` worked first try. pkgtb 70,438,876 B, sha256 072db7cfa99092edbd3306e4398e19b38accfcae078e00ff204c465fa6d882f6 (matches the artifact's sha256sums.txt).
- Official: curl SourceForge `.../GT-AX6000/Release/GT-AX6000_3006_102.9_0.zip/download` -> 66,648,301 B zip; pkgtb 70,438,392 B, sha256 f64453852fb3eacb996978cc2c0abc505e744c7a9a3a4522f0a98866e2c7a7e0 (equals the expected value).

Tools: apt `u-boot-tools device-tree-compiler squashfs-tools`; `dumpimage -l` and `dumpimage -T flat_dt -p N -o` worked for the outer FIT and the nested bootfs FIT (34 items); `unsquashfs -d -no-xattrs`.

Decisive results
- Same FIT layout. bootfs: 31/34 items identical (all dtbs); atf, uboot (banner date) and kernel (6,432,937 vs 6,432,454 B) differ. Rootfs squashfs same padded size.
- Rootfs: 3,939 entries each, 3,935 common. Only in CI: usr/sbin/webs_upgrade.sh + 3 empty dirs (lib/modules/4.19.183/kernel/project/...); only in official: 4 empty dirs (.../kernel/workspace/...). 22 size diffs, 49 mode diffs (umask 002 vs 022). 82 of 3,098 regular files differ; all 153 .ko identical; 575 symlinks identical.
- Noise: timestamps/build-id (motd, image_version, busybox, lighttpd...), embedded build path (/project/src vs /workspace/build/amng.gtax6000), mode bits, locale (www/Lang_Hdr.txt).
- NOT noise: official was built with MERLINUPDATE=y (rom/rtconfig has RTCONFIG_MERLINUPDATE=y only there; release/src-rt/Makefile:3767 reads env MERLINUPDATE; tools/build-all:18 has it commented out). The CI image therefore ships ASUS's webs_update.sh/webs_note.sh/webs_upgrade.sh (dlcdnets.asus.com) instead of Merlin's; sbin/rc and libshared.so sizes differ accordingly.

Verdict: structurally reproduces the official image; not bit-identical; one real config difference (MERLINUPDATE). Suggest exporting `MERLINUPDATE=y` in the Build step (not done, out of scope).

Unverified: kernel/ATF payload not decompressed (no lzo tool); sbin/rc, libshared.so, libwpa_client.so, chilli_opt, lldpd code differences not disassembled.

Extracted trees kept in this sandbox at `/tmp/t2/x/{ci,off}/{rootfs,boot}` (plus bootfs.bin, rootfs.squashfs; classification in `/tmp/t2/x/classify.txt`, diffs in `/tmp/t2/x/diffs.txt`). Originals in `/tmp/t2/ci`, `/tmp/t2/off`. Ephemeral.
