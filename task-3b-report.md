# Task 3B report: disable_infosvr guard (3151f6c) vs baseline (55c9f3a), offline

STATUS: DONE. No code changes; nothing pushed except `reports`.

## Inputs
- Guard: run 40700438258, artifact gt-ax6000-3151f6c0... pkgtb 70,438,868 B, sha256 `49c2fb1cda094d80e83ab08e8723b85e1305c415256381ef1212227d28c64e2f`.
- Baseline: run 40690847523, artifact gt-ax6000-55c9f3ac... pkgtb 70,438,868 B, sha256 `434f8a5df922b8df02eebb036e65076f50d17699feb34b7bec1a0e96c6fe627a`.
- Both downloaded with `gh run download <run> -R bottobot/asuswrt-merlin.ng -n <name>`; no 403. Tools: apt `u-boot-tools squashfs-tools`; `dumpimage -T flat_dt -p 1 -o rootfs.sq`, `unsquashfs -no-xattrs`. Trees: /tmp/t3b/{a=guard,b=baseline}/rootfs (ephemeral).

## Rootfs diff
- Entries: 3,939 each. Entry list (path, type, size, mode, link target) differs in ONE line: `usr/sbin/chilli_opt` 305,976 vs 305,980 B (guard vs baseline). All modes and all 575 symlinks identical (152 symlinks point at rc; target lists identical in both). Hardlinks: none (unsquashfs "created 0 hardlinks").
- Regular files with differing sha256: 19:
  bin/busybox, lib/modules/4.19.183/modules.dep, rom/etc/image_version, rom/etc/motd, **sbin/rc**, usr/lib/libcrypto.so.3, libgcrypt.so.11.8.0, libgdbm.so.3.0.0, liblldpctl.so.4.8.0, libshared.so, usr/sbin/chilli_opt, lighttpd, lldpcli, lldpd, miniupnpd, miniupnpd-igdv2, openvpn, socat, stubby.
- Everything beyond sbin/rc is on the expected noise list (busybox, motd, image_version, lighttpd, libcrypto, libgcrypt, libgdbm, lldp*, libshared, chilli_opt, miniupnpd*, openvpn, socat, stubby, modules.dep). **No unexpected files; no added/removed paths.**
- sbin/rc: size 2,443,288 B in both, mode 500; `cmp -l` shows 1,851,972 differing bytes (code layout shifted, not a localized patch; same size likely from padding). Not disassembled.

## Strings evidence
- `strings -a sbin/rc | grep -c disable_infosvr`: guard 1 (string index 3444), baseline 0.
- `usr/sbin/infosvr`: present in both, sha256 `38c51b9d6dbc92321e2ee90bbdf03f89fc5ee676ba3d9946a615d57997f1860a` identical. (The guard only stops it being started; the binary stays.)

## Source grep (origin/ap-stripdown cef17c4, contains 3151f6c)
`grep -rln infosvr release/src/router --include=*.c --include=*.h --include=*.sh --include=Makefile | grep -v '^release/src/router/infosvr/'` hits 6 files:
- rc/watchdog.c: `infosvr_check()` (l.11127) returns if disable_infosvr=1, else calls start_infosvr() (l.11132); called l.11664. Not a direct exec.
- rc/services.c: l.4611 stop_infosvr; **l.4617 start_infosvr(), the only place `/usr/sbin/infosvr` is exec'd** (argv l.4619, `_eval` l.4632; guard at l.4627-4628 calls stop_infosvr and returns). Callers: l.12695 start_infosvr(); stops at 13154, 16204, 16222, 6622 (killall only).
- rc/rc.h: declarations only. rc/lan.c l.122-123 and rc/init.c l.26024: RTCONFIG_QTN comments/debug text only.
- Makefile: build/install rules for the infosvr dir (l.1736, 3431-3434).
Conclusion: no path other than start_infosvr() execs /usr/sbin/infosvr in these file types. Not covered by the grep: other extensions (e.g. .cpp, init scripts without .sh, nvram-driven shell in the image) and the non-rc rootfs; I did not search rootfs scripts for "infosvr".

## Unverified
- Runtime behavior (needs the device; none contacted). rc code not disassembled to confirm the guard sits at the start_infosvr() entry in the binary.
