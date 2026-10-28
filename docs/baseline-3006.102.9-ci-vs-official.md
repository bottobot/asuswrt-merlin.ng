# Baseline: CI-built 3006.102.9 vs the official GT-AX6000 3006.102.9 image

Purpose: show how closely this fork's GitHub Actions build reproduces the official
Asuswrt-Merlin 3006.102.9 firmware for the GT-AX6000, before anything is stripped, so
that later differences can be traced to commits in this fork.

Source state: upstream `3006.102-wifi6` at `c73015d2b494` ("Bumped revision to
3006.102.9 final") plus README/workflow commits; CI run 40640600800 (commit `9c96e1f`).

## Inputs

| | file | bytes | sha256 |
|---|---|---|---|
| CI | `GT-AX6000_3006_102.9_0_nand_squashfs.pkgtb` (artifact `gt-ax6000-9c96e1f8426de963d6db28400437f8827c0862c7`) | 70,438,876 | `072db7cfa99092edbd3306e4398e19b38accfcae078e00ff204c465fa6d882f6` |
| Official | `GT-AX6000_3006_102.9_0_nand_squashfs.pkgtb` (from `GT-AX6000_3006_102.9_0.zip`, 66,648,301 B, SourceForge) | 70,438,392 | `f64453852fb3eacb996978cc2c0abc505e744c7a9a3a4522f0a98866e2c7a7e0` (matches the published value) |

Tools: `dumpimage -l` / `dumpimage -T flat_dt -p N` (u-boot-tools) for the outer FIT and the
nested "bootfs" FIT, `unsquashfs -no-xattrs` (squashfs-tools), `cmp -l`, `strings`, `readelf`.
Both packages are the same layout: outer FIT with `bootfs_4912_a0+` (a nested FIT) and
`nand_squashfs` (rootfs); default configuration `conf_4912_a0+_nand_squashfs`.

## Package structure

| node | CI size | official size | identical content |
|---|---|---|---|
| outer `bootfs_4912_a0+` | 10,877,964 | 10,877,480 | no (contains the 3 differing items below) |
| outer `nand_squashfs` (rootfs) | 59,559,936 | 59,559,936 | no (see below) |
| bootfs `atf` | 33,120 | 33,120 | no (embeds build time) |
| bootfs `uboot` | 2,780,304 | 2,780,304 | no (banner `U-Boot 2019.07 (Oct 28 2026 - 06:58:36 +0000)` vs `(Sep 23 2026 - 16:24:53 -0400)`) |
| bootfs `kernel` (4.19.183, lzo) | 6,432,937 | 6,432,454 | no (+483 B; cause not isolated, see Unverified) |
| bootfs other 30 items (device trees, etc.) | | | identical sizes and hashes |

The bootfs FIT has 34 items; 31 are bit-identical (all device trees and `fdt_uboot`).
The squashfs rootfs images have the same size after padding but different compressed
payload (59,558,997 vs 59,558,957 B used).

## Rootfs file list

3,939 entries in each image (`find -printf '%P %y %s %m'`).

* Paths present in both: 3,935. Types identical for all of them.
* Only in CI: `usr/sbin/webs_upgrade.sh` (a regular file) and 3 empty directories
  `lib/modules/4.19.183/kernel/project/{,src/,src/release}`.
* Only in official: 4 empty directories `lib/modules/4.19.183/kernel/workspace/{,build/,build/amng.gtax6000/,build/amng.gtax6000/release}`.
  (Same empty directories, named after each build's checkout path: `/project/src` in CI,
  `/workspace/build/amng.gtax6000` for the official build.)
* Size differs for 22 common paths; mode differs for 49 common paths.
* Content differs for 82 regular files out of 3,098 (all 153 kernel modules `*.ko` are bit-identical).

## Content differences, classified

1. **Build timestamp / build id only (trivially explained)**: `rom/etc/motd`, `rom/etc/image_version`
   (`5042p1GW3010657` vs `5042p1GW2661624`), `bin/busybox` (30 bytes; banner date),
   `usr/sbin/lighttpd` (18 bytes), `usr/lib/libgdbm.so.3.0.0` (9), `usr/sbin/rdisc6` (4),
   `usr/sbin/socat` (9), `usr/sbin/wget` (embedded compile date), `usr/sbin/stubby`, `usr/sbin/lldpd` ("Built on").
2. **Absolute build path embedded (same size or a few bytes shift)**: the CI tree lives at
   `/project/src/release/...`, the official at `/workspace/build/amng.gtax6000/release/...`.
   Affects about 60 ELF files (libnl*, net-snmp, lighttpd modules `mod_*.so`, ffmpeg libs, jq,
   openvpn, miniupnpd, ipset, libwpa_client, ...). Same-size files with many differing bytes
   (e.g. `libnl-route-3.so`, 303,607 bytes differ) are not explained by the strings alone (cause of the shifted layout not isolated); the check made was
   `strings -a | diff`, which shows only path/date lines for them (2-4 diff lines each), so no source-level difference is indicated.
   `modules.dep` / `modules.order` differ only by module path prefix and ordering.
3. **File mode noise**: 49 paths, almost all `rom/etc/*`, differ by group-write bit
   (CI `644`/`755`, official `664`/`775`), i.e. the official build ran with umask 002 and CI with 022.
4. **Locale noise**: `www/Lang_Hdr.txt` has UTF-8 language names in CI and `?` placeholders in
   the official image (452 vs 395 B). The CI output is the more correct one.
5. **Unexplained by timestamp/build-id/path: real configuration difference.**
   The official image was built with `MERLINUPDATE=y`; this fork's CI does not set it.
   Evidence: `rom/rtconfig` has `RTCONFIG_MERLINUPDATE=y` only in the official image.
   `release/src-rt/Makefile:3767` adds that flag when the environment variable `MERLINUPDATE=y`
   is set, and `tools/build-all:18` has it commented out. Consequences in the CI image:
   * `usr/sbin/webs_update.sh` (16,811 vs 4,021 B) and `usr/sbin/webs_note.sh` (4,774 vs 1,786 B) are
     ASUS's stock scripts instead of Merlin's `merlin_webs_update.sh` / `merlin_webs_note.sh`; they
     point at `dlcdnets.asus.com` instead of `fwupdate.asuswrt-merlin.net`.
   * `usr/sbin/webs_upgrade.sh` (ASUS auto-upgrade script) exists only in the CI image.
   * `sbin/rc` (2,439,184 vs 2,443,288 B), `usr/lib/libshared.so` (+20 B) and probably
     `libwpa_client.so`, `chilli_opt`, `lldpd` compile `#ifdef RTCONFIG_MERLINUPDATE` code
     differently or were rebuilt with other flags (size differs; not fully diffed).
   `webs_upgrade.sh` is a phone-home path that matters for the later strip-down.

Everything not in the lists above is byte-identical: 3,016 of 3,098 regular files, all 153 kernel modules,
all symlinks (575 each, same targets), and 31 of 34 bootfs items.

## Verdict

The fork's CI build reproduces the official 3006.102.9 GT-AX6000 image's structure exactly
(same FIT layout, same 3,935 common paths, same kernel version, same module set, 153/153 `.ko`
bit-identical), and the great majority of differences are timestamps, build-id, embedded checkout
paths, umask-dependent modes and locale. It is **not** a bit-for-bit reproduction, and one
difference is not build noise: the CI build lacks `MERLINUPDATE=y`, so it ships ASUS's update
scripts (including `webs_upgrade.sh`) rather than Merlin's. Setting `MERLINUPDATE=y` in the
workflow's Build step would remove that difference; that was not changed here (this task is
read-only on sources).

## Unverified

* The +483 B in the kernel image and the differing ATF payload were not decompressed (no lzo tool installed);
  the nearby evidence (U-Boot banner date, same `4.19.183` version string, identical modules) points to
  build time and path strings only.
* For `sbin/rc`, `libshared.so`, `libwpa_client.so`, `chilli_opt`, `lldpd` the code differences were not
  disassembled; the MERLINUPDATE attribution is by the rtconfig difference and sizes.

<details><summary>Raw lists</summary>

### Content-differing regular files (path | type | CI bytes | official bytes | differing bytes by cmp -l)

```
bin/busybox | ELF 32-bit L | 527436 | 527436 | 30 ; lib/libnl-cli-3.so.200.20.0 | ELF 32-bit L | 42972 | 42972 | 21735
lib/libnl-genl-3.so.200.20.0 | ELF 32-bit L | 22588 | 22588 | 12753 ; lib/libnl-idiag-3.so.200.20.0 | ELF 32-bit L | 34836 | 34836 | 17199
lib/libnl-nf-3.so.200.20.0 | ELF 32-bit L | 102680 | 102680 | 62451 ; lib/libnl-route-3.so.200.20.0 | ELF 32-bit L | 415100 | 415100 | 303607
lib/libnl/cli/cls/basic.so | ELF 32-bit L | 17188 | 17248 | 6896 ; lib/libnl/cli/cls/cgroup.so | ELF 32-bit L | 16600 | 16660 | 6277
lib/libnl/cli/qdisc/bfifo.so | ELF 32-bit L | 16724 | 16784 | 6698 ; lib/libnl/cli/qdisc/blackhole.so | ELF 32-bit L | 16064 | 16120 | 6043
lib/libnl/cli/qdisc/fq_codel.so | ELF 32-bit L | 17576 | 17636 | 6827 ; lib/libnl/cli/qdisc/htb.so | ELF 32-bit L | 23360 | 23416 | 7965
lib/libnl/cli/qdisc/ingress.so | ELF 32-bit L | 16040 | 16100 | 6026 ; lib/libnl/cli/qdisc/pfifo.so | ELF 32-bit L | 16500 | 16560 | 6527
lib/libnl/cli/qdisc/plug.so | ELF 32-bit L | 21140 | 21200 | 6528 ; lib/modules/4.19.183/modules.dep | ASCII text | 8949 | 9111 | 8367
lib/modules/4.19.183/modules.order | ASCII text | 6434 | 6506 | 411 ; rom/etc/image_version | ASCII text | 16 | 16 | 6
rom/etc/motd | ASCII text | 69 | 69 | 9 ; rom/rtconfig | ASCII text | 4431 | 4455 | 1523
sbin/rc | ELF 32-bit L | 2439184 | 2443288 | 2095878 ; usr/bin/jq | ELF 32-bit L | 889876 | 889876 | 189541
usr/bin/net-snmp-config | POSIX shell | 32292 | 32724 | 28958 ; usr/bin/net-snmp-create-v3-user | POSIX shell | 3167 | 3185 | 303
usr/bin/usbmuxd | ELF 32-bit L | 207720 | 207720 | 167857 ; usr/lib/libatalk.so.6.0.0 | ELF 32-bit L | 319912 | 319912 | 227700
usr/lib/libavahi-core.so.7.1.0 | ELF 32-bit L | 232200 | 232200 | 180675 ; usr/lib/libavcodec.so.58 | ELF 32-bit L | 1589428 | 1589428 | 110688
usr/lib/libavformat.so.58 | ELF 32-bit L | 697436 | 697436 | 7734 ; usr/lib/libavutil.so.56 | ELF 32-bit L | 457240 | 457240 | 5503
usr/lib/libcrypto.so.3 | ELF 32-bit L | 4484332 | 4484332 | 187392 ; usr/lib/libgcrypt.so.11.8.0 | ELF 32-bit L | 544048 | 544048 | 462550
usr/lib/libgdbm.so.3.0.0 | ELF 32-bit L | 17884 | 17884 | 9 ; usr/lib/libipset.so.13.1.0 | ELF 32-bit L | 132040 | 132040 | 59908
usr/lib/libiptc.so | ELF 32-bit L | 5324 | 5324 | 535 ; usr/lib/libjq.so.1.0.4 | ELF 32-bit L | 395776 | 395776 | 325727
usr/lib/liblightsql.so | ELF 32-bit L | 9532 | 9532 | 2060 ; usr/lib/liblldpctl.so.4.8.0 | ELF 32-bit L | 71288 | 71288 | 51933
usr/lib/libnetfilter_conntrack.so.3 | ELF 32-bit L | 136824 | 136824 | 102124 ; usr/lib/libnetfilter_cttimeout.so.1 | ELF 32-bit L | 13800 | 13800 | 4634
usr/lib/libnetsnmp.so.35.0.0 | ELF 32-bit L | 326732 | 326732 | 12242 ; usr/lib/libnetsnmpagent.so.35.0.0 | ELF 32-bit L | 175892 | 175892 | 108249
usr/lib/libnetsnmpmibs.so.35.0.0 | ELF 32-bit L | 239624 | 239624 | 157361 ; usr/lib/libpcreposix.so.0.0.1 | ELF 32-bit L | 5460 | 5460 | 1853
usr/lib/libshared.so | ELF 32-bit L | 767584 | 767604 | 528800 ; usr/lib/libusb-0.1.so.4 | ELF 32-bit L | 13732 | 13732 | 6544
usr/lib/libvorbis.so.0 | ELF 32-bit L | 161488 | 161488 | 103485 ; usr/lib/libwpa_client.so | ELF 32-bit L | 140352 | 140536 | 50769
usr/lib/mod_access.so | ELF 32-bit L | 5452 | 5452 | 1966 ; usr/lib/mod_alias.so | ELF 32-bit L | 9560 | 9560 | 2312
usr/lib/mod_auth.so | ELF 32-bit L | 26484 | 26484 | 14566 ; usr/lib/mod_compress.so | ELF 32-bit L | 9668 | 9668 | 3616
usr/lib/mod_dirlisting.so | ELF 32-bit L | 18084 | 18084 | 9429 ; usr/lib/mod_indexfile.so | ELF 32-bit L | 9588 | 9588 | 2390
usr/lib/mod_redirect.so | ELF 32-bit L | 9608 | 9608 | 3124 ; usr/lib/mod_rewrite.so | ELF 32-bit L | 9676 | 9676 | 4322
usr/lib/mod_staticfile.so | ELF 32-bit L | 13780 | 13780 | 5696 ; usr/lib/mod_userdir.so | ELF 32-bit L | 9688 | 9688 | 2876
usr/lib/mod_usertrack.so | ELF 32-bit L | 9660 | 9660 | 2987 ; usr/lib/mod_webdav.so | ELF 32-bit L | 71708 | 71708 | 45587
usr/lib/netatalk/uams_dhx2_passwd.so | ELF 32-bit L | 13776 | 13776 | 5273 ; usr/lib/openvpn-plugin-auth-pam.so | ELF 32-bit L | 13704 | 13704 | 8399
usr/lib/pam_unix.so | ELF 32-bit L | 5352 | 5352 | 1488 ; usr/sbin/avahi-daemon | ELF 32-bit L | 67748 | 67748 | 45322
usr/sbin/chilli_opt | ELF 32-bit L | 305976 | 305980 | 239076 ; usr/sbin/ipset | ELF 32-bit L | 111196 | 111196 | 53848
usr/sbin/lighttpd | ELF 32-bit L | 212716 | 212716 | 18 ; usr/sbin/lldpcli | ELF 32-bit L | 83568 | 83568 | 64362
usr/sbin/lldpd | ELF 32-bit L | 143500 | 147596 | 119638 ; usr/sbin/miniupnpd | ELF 32-bit L | 129692 | 129692 | 23399
usr/sbin/miniupnpd-igdv2 | ELF 32-bit L | 158432 | 158432 | 27934 ; usr/sbin/openvpn | ELF 32-bit L | 752972 | 752972 | 82419
usr/sbin/rdisc6 | ELF 32-bit L | 13856 | 13856 | 4 ; usr/sbin/snmpd | ELF 32-bit L | 18240 | 18240 | 8559
usr/sbin/socat | ELF 32-bit L | 170472 | 170472 | 9 ; usr/sbin/stubby | ELF 32-bit L | 335140 | 335140 | 2830
usr/sbin/traceroute | ELF 32-bit L | 65756 | 65756 | 20455 ; usr/sbin/usbmode | ELF 32-bit L | 18228 | 18228 | 10000
usr/sbin/webs_note.sh | POSIX shell | 4774 | 1786 | 1715 ; usr/sbin/webs_update.sh | POSIX shell | 16811 | 4021 | 3843
usr/sbin/wget | ELF 32-bit L | 321300 | 321300 | 2727 ; www/Lang_Hdr.txt | Unicode text | 452 | 395 | 357
```

### Mode differences (49 paths; CI mode / official mode)

```
bin/qdf_cv_lvl.sh 644/664; rom/etc/adsl1 755/775; rom/etc/adsl1/adsl_phy.bin 644/664; rom/etc/arl 755/775
rom/etc/default.script 755/775; rom/etc/dhcp 755/775; rom/etc/dhcp/dhcp_getdata 755/775; rom/etc/dhcp6c.conf.sample 644/664
rom/etc/dhcp6s.conf.sample 644/664; rom/etc/dyndscp.sh 755/775; rom/etc/ethertypes 644/664; rom/etc/filesystems 644/664
rom/etc/fstab 444/464; rom/etc/get_rootfs_dev.sh 755/775; rom/etc/hp_wrapper.sh 755/775; rom/etc/init.d/gre-tunnel-drivers.sh 755/775
rom/etc/init.d/system-config.sh 755/775; rom/etc/init.d/x2serdes_init.sh 755/775; rom/etc/init.d/xserdes_init.sh 755/775; rom/etc/iproute2 755/775
rom/etc/iproute2/ematch_map 644/664; rom/etc/ipv6_start.sample 755/775; rom/etc/ld.so.conf 644/664; rom/etc/lte_start.sh 755/775
rom/etc/make_mmc_links.sh 755/775; rom/etc/make_static_devnodes.sh 755/775; rom/etc/mdk 755/775; rom/etc/modprobe.conf 644/664
rom/etc/mptcp.sh 755/775; rom/etc/nsswitch.conf 644/664; rom/etc/openssl.cnf 644/664; rom/etc/ppp/chap-secrets 644/664
rom/etc/ppp/ip-down 755/775; rom/etc/ppp/ip-up 755/775; rom/etc/ppp/options 644/664; rom/etc/ppp/pap-secrets 644/664
rom/etc/profile 644/664; rom/etc/protocols 644/664; rom/etc/radvd.conf.sample 644/664; rom/etc/redsocks.sh 755/775
rom/etc/resolv.conf 644/664; rom/etc/services 644/664; rom/etc/soft_bridge 755/775; rom/etc/ssl 755/775
rom/etc/ssl/certs/dh2048.pem 644/664; rom/etc/test_sig.trf 755/775; rom/etc/vlan 755/775; rom/tmpfs.json 644/664
usr/sbin/webs_note.sh 644/755
```

</details>

Extracted trees (sandbox only, not committed): `/tmp/t2/x/{ci,off}/{rootfs,boot}`.
