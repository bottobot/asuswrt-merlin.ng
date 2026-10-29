# PLAN.md — GT-AX6000 AP strip-down: phased goals + granular tasks

FORMAT: machine-readable. Each task: `ID|tier|est_min|depends|action|done_when`. tier: H=haiku-class S=sonnet-class O=opus-class(review/decide only). est_min<=20 always. Any task found >20min at execution => split, do not continue.
BASE: Merlin 3006.102.9, branch `3006.102-wifi6` @ c73015d. SDK `release/src-rt-5.04axhnd.675x`, target `make gt-ax6000`. Service wiring: `release/src/router/rc/services.c`. Build flags: `release/src-rt/target.mak` (`export GT-AX6000`). Package gating: `release/src/router/Makefile` (`obj-$(RTCONFIG_X)`, `obj-y`=unconditional).
CI: `.github/workflows/build-gt-ax6000.yml`. Full build ~63min on ubuntu-latest in gnuton toolchain container.

## REVIEW OF EXISTING PLAN (README.md "How"/"Status")

R1|FACT|CI run 40640600800: `make gt-ax6000` SUCCEEDED (63min), image GT-AX6000_3006_102.9_0_nand_squashfs.pkgtb 70438876B sha256 072db7cf...; both artifacts uploaded (IDs 12798202289, 12797389280). Job marked failed only by `EACCES /__w/_temp/_runner_file_commands/set_output_*` in upload-artifact post-step. Cause: container `--user docker`, runner creates per-step files as root after the early chmod. Conclusion: build pipeline works; README "Status: early" understates it.
R2|GAP|README says "unpack both images and compare contents" but no tooling, no script, no official-image fetch step exists. pkgtb = U-Boot FIT container; needs `dumpimage`(u-boot-tools)+`unsquashfs`; rootfs is UBI/squashfs. Must be a concrete milestone (P1).
R3|GAP|No recovery/rollback procedure documented before first flash. GT-AX6000 is U-Boot (BCM4912) class: rescue via ASUS Firmware Restoration / rescue-mode TFTP, dual boot partitions. Must precede any hardware test (P2).
R4|GAP|No baseline measurement of running state (listeners, processes, radios, VLANs) => no objective pass/fail for "did not break the device". Add baseline capture script + diff (P2).
R5|ORDER|README conflates "switch off" and "compile out". Correct order per service: (a) runtime nvram/kill test on live device, no rebuild, minutes; (b) rc guard commit (`access_point_mode()` conditional), 1 rebuild; (c) compile-out via target.mak flag or Makefile obj gating, 1 rebuild. Do (a) for all targets before any (b)/(c) to avoid 63min cycles on guesses.
R6|FACT|Runtime knobs already present, zero-rebuild: `wanduck_down=1` (no_need_to_start_wanduck), `networkmap_enable=0`, `cfg_master=0` (cfg_server only runs when cfg_master=1 && (router||AP)), `ava_verb`. infosvr has NO runtime off switch except RTCONFIG_MODEM_BRIDGE+modem_bridge; needs rc guard (b).
R7|FACT|`infosvr`, `networkmap`, `avahi`, `amas-utils`, `sysstate` are `obj-y` in router/Makefile => compile-out needs Makefile edits, not only flags. `wlc_nt`=NOTIFICATION_CENTER, `asd`=ASD, `aaews/mastiff/asusnatnl`=TUNNEL, `dblog`=DBLOG, `cfg_mnt`=CFGSYNC.
R8|RISK|Guest Network Pro = MTLANCFG=y; 3006 multi-LAN code shares helpers with AMAS/cfg_mnt (`amas_wgn_shared.h`, `mtlan_utils.h`). Disabling AMAS=y may break VLAN guest. Treat AMAS compile-out as P5 experiment behind its own gate, never bundled.
R9|RISK|Large flag removals (BWDPI, VPN stack, USB/Samba, TOR, SNMPD) are attack-surface wins but each is a 63min build + flash cycle. Batch max 3 flags per build; one commit per flag so bisect works.
R10|GAP|No CI cache. Optional: cache `$SDK_DIR/hostTools` + toolchain outputs; low priority, risk of stale objects. Not a milestone until P4.
R11|DELETE|README line "Builds will be tested on hardware I can afford to brick" => replace with explicit P2 recovery gate.

## PHASES

P0 CI green + reproducible unmodified build
P1 Image comparison tooling (ours vs official)
P2 Hardware safety: recovery drill + runtime baseline
P3 Runtime disable (nvram/rc guards), AP-mode only, no package removal
P4 Compile-out tier 1: cloud/mesh/telemetry daemons
P5 Compile-out tier 2: large subsystems (VPN, DPI, USB, misc servers)
P6 Hardening + release discipline

Gate rule: phase N+1 starts only when all P_N `done_when` are met and recorded in PLAN-STATUS.md.

## P0 CI GREEN

P0.1|S|15|-|Edit workflow: run container as root (drop `--user docker`), add step `sudo -u docker` or `chown -R docker` only for build dir; OR keep docker user and add pre-upload step `sudo chmod -R a+rwX /__w/_temp` immediately before each upload-artifact. Pick one, comment why.|workflow_dispatch run: all steps green, 2 artifacts present
P0.2|H|5|P0.1|Add `concurrency: {group: build-${{github.ref}}, cancel-in-progress: true}` to workflow.|yaml valid, push of 2 commits cancels first run
P0.3|H|10|P0.1|Add step after build: `echo "sha256=$(sha256sum image|cut -c1-64)" >> $GITHUB_STEP_SUMMARY`; also `ls -l $SDK_DIR/image/`.|step summary shows sha + size
P0.4|H|10|P0.1|Add `retention-days: 14` to artifact uploads; add `paths-ignore` for `PLAN*.md`, `docs/**`.|yaml valid
P0.5|S|15|P0.1|Second clean CI build of identical commit. Record both sha256 in PLAN-STATUS.md. Expect differ (timestamps). Note delta size.|2 sha recorded
P0.6|H|10|P0.5|Add workflow_dispatch input `ref_to_build` (default branch) so any commit can be rebuilt without push.|dispatch with input works
P0.7|O|10|P0.5|Review: confirm image name/version string matches official naming (`GT-AX6000_3006_102.9_0_nand_squashfs.pkgtb`). Decide version suffix policy for fork builds (e.g. `_ap1`) to avoid mistaking images.|decision in PLAN-STATUS.md

## P1 IMAGE COMPARISON

P1.1|S|15|-|Write `tools/fw-unpack.sh <pkgtb> <outdir>`: `dumpimage -l`; extract FIT sub-images with `dumpimage -T flat_dt -p N`; detect squashfs via `file`/magic; `unsquashfs -d outdir/rootfs`. Deps: u-boot-tools, squashfs-tools. Script fails loudly if magic not found.|runs on CI artifact; rootfs/ populated
P1.2|H|10|P1.1|Write `tools/fw-manifest.sh <rootdir>`: emit sorted `path|mode|size|sha256` for all files; symlinks as `path|link|target`.|manifest.txt produced, deterministic across 2 runs
P1.3|H|15|P1.2|Write `tools/fw-diff.sh <manifestA> <manifestB>`: classify ADDED/REMOVED/CHANGED; print counts + list.|output on two CI builds of same commit shows only expected timestamp-bearing files
P1.4|S|15|P1.1|Document official image source URL for 3006.102.9 GT-AX6000 (RMerl release mirror). Add CI job `compare` (workflow_dispatch, input `official_url`): download, unpack both, run diff, upload `diff.txt`.|diff.txt artifact present
P1.5|O|15|P1.4|Review diff of unmodified-source CI build vs official. Classify every CHANGED file: build-timestamp / path-embedded / toolchain / unexplained. Unexplained count must be 0 or each listed with reason.|table in PLAN-STATUS.md; P1 gate
P1.6|H|10|P1.3|Add `tools/README.md` (machine-readable, 20 lines max) listing scripts, args, deps.|file exists
P1.7|S|15|P1.1|Extend fw-unpack to also dump `/etc/init.d`, `/sbin/rc` symlink list and `strings rc|grep -E '^(start|stop)_'` into `rc-services.txt` for later rc-change verification.|file produced

## P2 HARDWARE SAFETY + BASELINE

P2.1|S|15|-|Write `docs/RECOVERY.md`: steps for GT-AX6000 rescue mode (power+reset hold, LED pattern), ASUS Firmware Restoration tool, TFTP 192.168.1.1 fallback, U-Boot dual-image note. Cite official ASUS FAQ URL.|doc exists
P2.2|H|10|P2.1|Perform recovery drill ON DEVICE with OFFICIAL 3006.102.9: enter rescue mode, restore official image, boot, verify version in GUI. Record time taken.|PLAN-STATUS.md: drill PASS + minutes
P2.3|H|15|-|Write `tools/ap-baseline.sh` (runs on router via ssh, busybox-only): outputs `ps w`, `netstat -lnp` (tcp+udp), `nvram get sw_mode`, `wl -i eth6 status; wl -i eth7 status` (confirm iface names first), `brctl show`, `cat /proc/net/vlan/config`, `ip -d link | grep vlan`, `nvram show | grep -E '^(wl[0-9]_ssid|wl[0-9].[0-9]_ssid|vlan|apg|mtlan|sdn)'`, uptime, free. One file per section under `baseline/<label>/`.|runs clean over ssh, 8 files
P2.4|H|10|P2.3|Write `tools/ap-diff.sh <labelA> <labelB>`: diff per section, suppress PIDs/timestamps.|clean diff of two captures 1min apart = empty
P2.5|H|10|P2.3|Capture `baseline/official-3006.102.9/` on official image in AP mode with both radios + guest VLAN configured.|committed (sanitize MACs/SSIDs/keys via sed before commit)
P2.6|S|10|P2.5|From netstat baseline produce `docs/LISTENERS.md`: table `port|proto|process|needed_in_AP(y/n/?)|plan_ref`. Fill n/? only; y requires reason.|table complete, every listener has a row
P2.7|H|15|P0.5|Flash CI-built UNMODIFIED image. Capture `baseline/ci-unmodified/`. Run ap-diff vs official.|diff empty except version/build strings; P2 gate
P2.8|S|10|P2.7|Write `docs/TESTPLAN.md`: 10-item manual checklist (2.4G client assoc, 5G client assoc, guest SSID gets VLAN tag seen on upstream switch, GUI https reachable, ssh reachable, reboot survives, uptime>30min no wl reset in dmesg, upstream DHCP relayed to clients, WPA3 SSID works, LED/button sanity).|doc exists; used from P3 on

## P3 RUNTIME DISABLE (AP mode only, no package removal)

Ordering per service: 3.x.a runtime test via ssh (no build) -> 3.x.b rc guard commit -> single batch build -> flash -> ap-diff + TESTPLAN.
Guard pattern for rc: `if (access_point_mode()) return 0;` at top of `start_<svc>()`, plus matching no-op in `stop_` if needed. Each guard = 1 commit, message `rc: do not start <svc> in AP mode`.

P3.1a|H|10|P2.7|On device: `nvram set wanduck_down=1; nvram commit; reboot`. Capture baseline `rt-wanduck`. Confirm no listener 18017/18018, no wanduck proc, GUI still reports AP mode OK.|diff shows only wanduck gone
P3.1b|S|15|P3.1a|Commit: in `no_need_to_start_wanduck()` add `if (access_point_mode()) return 1;` (and same in `start_mtwanduck`). Note: wanduck also drives GUI "internet status"/redirect in AP; check `rc/wanduck.c` for AP-only code paths and list them in commit message.|builds; commit on branch
P3.2a|H|5|P2.7|On device: `killall infosvr`. Confirm UDP 9999 closed; GUI+ASUS app discovery expected broken, acceptable.|note in PLAN-STATUS.md
P3.2b|H|10|P3.2a|Commit: `start_infosvr()` guard `if (access_point_mode()) return 0;`.|builds
P3.3a|H|10|P2.7|On device: `nvram set cfg_master=0; nvram commit; reboot`? CAUTION: cfg_master=0 in AP may trigger cfg_client (RE-mode) path (`x_Setting==1 && cfg_group==""`). Instead test `killall cfg_server` only; confirm 7788 closed, guest VLANs still present after 10min.|note result; if VLAN lost => STOP, escalate to O review
P3.3b|S|15|P3.3a|Commit: in `start_cfgsync()` add AP-mode early return BEFORE both server and client branches; grep rc for `cfg_pause`,`cfg_alive` users that may block (`rc/init.c`, `rc/lan.c:4718`).|builds; grep list in commit msg
P3.4a|H|5|P2.7|On device: `killall avahi-daemon`. Confirm UDP 5353 closed, radios unaffected.|note
P3.4b|H|10|P3.4a|Commit: `start_mdns()` AP guard. Check `restart_mdns()` callers (services.c:8097) for AP paths.|builds
P3.5a|H|5|P2.7|On device: `nvram set networkmap_enable=0; nvram commit; killall networkmap`. GUI client list will be empty, acceptable.|note
P3.5b|H|10|P3.5a|Commit: `start_networkmap()` AP guard.|builds
P3.6a|H|10|P2.7|On device: kill `asd`, `conn_diag`, `wlc_nt`, `dblog`, `sysstate`, `lldpd` one at a time, 2min each, check radios+GUI each. Record which are safe.|table in PLAN-STATUS.md
P3.6b|S|20|P3.6a|Commits (one per svc, only those marked safe): AP guards in `start_asd`, `start_conn_diag`, `start_wlc_nt`, `start_dblog`, `start_amas_lldpd`. Skip sysstate (obj-y, used by GUI).|builds
P3.7|H|10|P3.6b|Grep `services.c` lines 12500-12970 (boot start list) for any other `start_*` whose daemon appears in LISTENERS.md with needed=n and no guard yet; add to PLAN-STATUS.md as P3.8+.|list
P3.8|S|15|P3.6b|Batch build (max all P3 commits). Flash. Capture `baseline/p3`. ap-diff vs ci-unmodified: expect removed procs exactly = guarded set. Run TESTPLAN.|TESTPLAN 10/10; P3 gate
P3.9|O|15|P3.8|Review every guard diff for: repeater/`re_mode` regressions, `notify_rc("restart_x")` paths that will now log errors, GUI pages that poll the killed daemons (`www/*.asp` grep). Decide which GUI warnings to accept.|review notes
P3.10|H|10|P3.8|Update README.md Status + link PLAN.md; update LISTENERS.md plan_ref column.|committed

## P4 COMPILE-OUT TIER 1 (cloud/mesh/telemetry)

Each flag: 1 commit `target.mak: GT-AX6000 <FLAG>=n` (+ Makefile `obj-y`->`obj-$(RTCONFIG_X)` when needed). Max 3 flags per build. After each build: fw-diff vs previous (expect only removed binaries/libs), flash, ap-diff, TESTPLAN.

P4.1|S|15|P3.8|Pre-check script `tools/flag-impact.sh <FLAG>`: grep `#ifdef RTCONFIG_<FLAG>` counts in rc/, httpd/, www/, shared/; list packages gated by it in router/Makefile.|script output for each P4 flag saved to docs/flags/<FLAG>.txt
P4.2|H|10|P4.1|Commit `ASD=n` (asd daemon, ASUS security daemon cloud fetch).|builds
P4.3|H|10|P4.1|Commit `DBLOG=n`.|builds
P4.4|H|10|P4.1|Commit `CONNDIAG=n` (in HND-94912_BASE and GT-AX6000 line; override at end of GT-AX6000 line).|builds
P4.5|S|15|P4.2|Build batch A (P4.2-4.4). fw-diff: only asd/dblog/conn_diag binaries + libs removed. Flash, ap-diff, TESTPLAN.|pass
P4.6|S|15|P4.1|Commit: router/Makefile `obj-y += infosvr` -> `obj-$(RTCONFIG_INFOSVR)`; add `INFOSVR=n` to GT-AX6000; wrap `start_infosvr` call sites in `#ifdef RTCONFIG_INFOSVR`. Check `shared/discover.h`/httpd for infosvr-only symbols.|builds
P4.7|S|15|P4.1|Commit: `NATNL_AICLOUD=n NATNL_AIHOME=n` (=> TUNNEL off => aaews/mastiff/asusnatnl dropped). grep httpd for `RTCONFIG_TUNNEL` GUI stubs.|builds
P4.8|H|10|P4.1|Commit `ALEXA=n GOOGLE_ASST=y->n`? Both are cloud assistant hooks; check `IFTTT` coupling in www.|builds
P4.9|S|15|P4.6|Build batch B (P4.6-4.8). fw-diff, flash, ap-diff, TESTPLAN.|pass
P4.10|S|15|P4.1|Commit: `obj-y += networkmap` -> gated `NETWORKMAP=n`; guard `start_networkmap` call sites; www client list page expected to show empty.|builds
P4.11|S|20|P4.1|Commit: `obj-y += avahi` -> gated by existing `MDNS` flag; `MDNS=n`. Check `TIMEMACHINE`/`MEDIASRV` need avahi (they do) => set `TIMEMACHINE=n MEDIASRV=n` in same batch, separate commits.|builds
P4.12|S|15|P4.10|Build batch C (P4.10-4.11). fw-diff, flash, ap-diff, TESTPLAN.|pass; P4 gate
P4.13|O|15|P4.12|Review cumulative diff vs official: list every removed binary; every remaining listener in LISTENERS.md must be needed=y.|table updated

## P5 COMPILE-OUT TIER 2 (large subsystems)

Each is its own batch (1 flag group per build) because blast radius is large.

P5.1|S|20|P4.12|`BWDPI=n` (Trend Micro DPI; also gates `networkmap` dep, `wrs`, `dcd`). Check `nvram` defaults referencing `bwdpi_*` in `shared/defaults.c` for GUI breakage.|builds; TESTPLAN pass
P5.2|S|20|P4.12|VPN: `OPENVPN=n WIREGUARD=n VPNC=n VPN_FUSION=n VPN_FUSION_MERLIN=n IPSEC=n ACCEL_PPTPD=n TOR=n`. 1 commit each, 1 build. www VPN pages will stub.|builds; TESTPLAN pass
P5.3|S|20|P4.12|USB/storage: `USB="" USBEXTRAS=n MEDIASRV=n SAMBA3="" NFS=n PRINTER=n TFAT=n NTFS="" HFS="" DISK_MONITOR=n HD_SPINDOWN=n MODEM=n USB_WAN_BACKUP=n XHCI=n`. High coupling risk => O review of flag-impact output before commit.|builds; TESTPLAN pass
P5.4|H|15|P4.12|Misc servers: `SNMPD=n UPNPIGD2=n QUAGGA=y->n MULTICASTIPTV=n CAPTIVE_PORTAL=n CP_FREEWIFI=n INSTANT_GUARD=n LETSENCRYPT=n EMAIL=n`.|builds; TESTPLAN pass
P5.5|S|15|P4.12|WAN-only: `DUALWAN=n MULTISERVICE_WAN=n MTPPP=n BONDING_WAN=n`. CAUTION: AP mode still uses wan ifname for upstream bridge; grep `rc/lan.c` for DUALWAN in `access_point_mode()` paths first.|builds; TESTPLAN pass
P5.6|O|20|P5.5|EXPERIMENT GATE: `AMAS=n` + `CFGSYNC_LOCSYNC=n` + `ETHOBD=n` + `DWB=n`. Precondition: flag-impact shows MTLANCFG paths compile without AMAS. If guest VLAN breaks => revert, keep rc guards from P3.3b only, document in PLAN-STATUS.md.|decision recorded
P5.7|S|15|P5.6|Cumulative fw-diff vs official + size table (image, rootfs, binary count).|table; P5 gate

## P6 HARDENING + RELEASE DISCIPLINE

P6.1|H|10|P5.7|Final `baseline/final` capture; LISTENERS.md every row needed=y with reason. Target: only 22/tcp (dropbear), 443/tcp (httpd), 53/udp if dnsmasq kept (decide), DHCP client ports.|table
P6.2|H|10|P5.7|Add `docs/CHANGES.md`: per-commit list `sha|flag_or_guard|removed_binaries|listener_change`.|generated from git log + fw-diff outputs
P6.3|S|15|P5.7|CI: on tag `v3006.102.9-ap<N>` run build + compare + attach image, sha256, diff.txt, manifest to a GitHub pre-release marked "not for use".|tag release works
P6.4|H|10|P5.7|README.md: replace Status section with link to PLAN-STATUS.md; keep warning block; remove R11 line.|committed
P6.5|S|20|P5.7|Rebase check: script `tools/upstream-check.sh` fetches RMerl `3006.102-wifi6`, lists new commits touching files we patched (rc/services.c, target.mak, router/Makefile).|script runs
P6.6|O|15|P6.5|Decide maintenance policy: rebase onto each Merlin point release vs stay pinned. Record.|decision

## EXECUTION RULES

E1 One task per worker invocation; worker gets: task line, file paths above, `done_when`. Worker returns: diff or output + 1-line result. No worker edits PLAN.md.
E2 Every rc guard uses `access_point_mode()` from shared (not raw `sw_mode()==SW_MODE_AP`) to also cover `re_mode` semantics; verify helper in `shared/shared.h`.
E3 Never batch a P5 flag group with any other group. Never batch >3 P4 flags.
E4 Every flash preceded by: CI green, fw-diff reviewed, recovery image on laptop. Every flash followed by: ap-diff + TESTPLAN within same session.
E5 PLAN-STATUS.md = append-only log: `date|task|result|sha|notes`. Gate decisions are O-tier only.
E6 Commit message format: `<area>: <imperative summary>` + body listing grep evidence and removed binaries. No model identifiers.
E7 If any task exceeds 20min: stop, split into subtasks in PLAN-STATUS.md, continue only on subtasks.
