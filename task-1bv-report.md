# Task 1b verification (run 40690847523, commit 55c9f3a)

Sandbox /tmp/t2 was wiped; recreated (apt squashfs-tools, device-tree-compiler, u-boot-tools; official zip from SourceForge, sha256 f64453852f... matches; new artifact id 12821346285 via `gh api .../zip`). compare.sh itself did not survive, so I ran the equivalent steps by hand: `dumpimage -T flat_dt -p 1`, `unsquashfs -no-xattrs`, sha256 of every regular file, `find -printf '%P %y %m'` diff.

New pkgtb: 70,438,868 B, sha256 434f8a5df922b8df02eebb036e65076f50d17699feb34b7bec1a0e96c6fe627a (equals sha256sums.txt in artifact).

- (a) PASS: `grep RTCONFIG_MERLINUPDATE rom/rtconfig` -> `=y` in both new and official.
- (b) PASS: usr/sbin/webs_upgrade.sh absent (ls: No such file).
- (c) PASS: `cmp` says webs_update.sh and webs_note.sh identical to official.
- (d) PASS: 77 content-differing regular files (was 82); file lists identical, all 77 were in the old 82. sbin/rc, chilli_opt, rtconfig, webs_* now identical. libshared.so same size (13 bytes differ). lldpd (147596 vs 143500) and libwpa_client.so (140536 vs 140352) still differ in size; `strings` diff and readelf show only build date, /workspace/build/amng.gtax6000 vs /project/src paths, /home/merlin/soft vs /home/docker toolchain paths, and .debug_*/.strtab length (debug-info strings). Path-length noise. Mode diffs: group-write bit on rom/etc/* (umask) plus empty build-path dirs; no other differences.

Commit 1011371b70 "docs: baseline after MERLINUPDATE=y (run 40690847523)" (markdown only, pushed).
Unverified: kernel/ATF payloads not decompressed.
