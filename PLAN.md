# PLAN.md v2 — GT-AX6000 AP strip-down: execution plan + status
fmt: machine-readable. task=`ID|tier|min|dep|status|action|done_when`. tier: H=haiku S=sonnet O=opus(review/gate only) U=owner(hardware, cannot delegate). min<=20; overrun => split in place, never continue. status: DONE|WIP|TODO|BLOCKED(reason).
facts_ref=docs/gt-ax6000-ap-plan.md (investigation: service inventory, flags, CVEs). baseline_ref=docs/baseline-3006.102.9-ci-vs-official.md. this file=single source for WHAT/ORDER/STATUS; v1 superseded.
base=Merlin 3006.102.9 (3006.102-wifi6 @c73015d). sdk=release/src-rt-5.04axhnd.675x make=gt-ax6000. flags=release/src-rt/target.mak:197-221. flag->RTCONFIG+forced deps=release/src-rt/Makefile. pkg gating=release/src/router/Makefile. rc=release/src/router/rc/{services,watchdog,lan,wan}.c.
ci=.github/workflows/build-gt-ax6000.yml (root container, clone+make as docker, MERLINUPDATE=y, digest-pinned, 45-63min). cloud sandbox: no build (no toolchain/docker/disk), artifact download blocked (blob 403) => all image work runs in CI.

## 1.CRITIQUE (v1 PLAN.md + docs/gt-ax6000-ap-plan.md §6)
C1|v1 E2 WRONG|on Broadcom `access_point_mode()`=sw_mode==3&&!wlc_psta (shared/shared.h:2074); does NOT exclude re_mode. v1 rule "use access_point_mode() to cover re_mode" false.
C2|v1 design WRONG|unconditional AP-mode guards change behaviour for every AP user and need a reflash to undo. Replace with opt-in nvram knobs `disable_<x>=1` (pattern already merged: disable_infosvr services.c:4612, watchdog.c:11119). Default unchanged; toggle on device; bisect without rebuild.
C3|v1 test method INVALID|v1 P3.xa "killall then observe": watchdog (watchdog.c:11489-11654) respawns networkmap cfg_server conn_diag mastiff amas_lib awsiot infosvr wanduck within one tick. Kill tests prove nothing. Need guarded build first, then on-device toggles.
C4|v1 cost model WRONG|v1 = one 63min build per daemon guard (~10 builds). v2 = ONE build carrying all opt-in guards; per-daemon testing is nvram+reboot (~3min each).
C5|v1 FACT WRONG|networkmap_enable=0 honoured only with RTCONFIG_DISABLE_NETWORKMAP (services.c:4453).
C6|v1 GAP|many targets PREBUILT for GT-AX6000 (cfg_mnt conn_diag networkmap asd nt_center aaews bwdpi; rc/prebuild/GT-AX6000/*.o). Compile-out = drop flag => prebuilt rc objects may fail to link. Need per-flag link-risk evidence before any build.
C7|v1 GAP|MDNS=n alone swaps avahi for mDNSResponder (router/Makefile:1596-1606) unless TIMEMACHINE MEDIASRV BWDPI also n. Flags force each other (AMAS=>CFGSYNC CONNDIAG DBLOG NOTIFICATION_CENTER; BWDPI/AMAS=>NOTIFICATION_CENTER; NATNL_*/ALEXA=>TUNNEL). Setting one =n can be silently overridden.
C8|v1 GAP|hardware tasks tiered H; hardware is owner-only (tier U). Agents cannot flash or observe radios.
C9|v1 GAP|watchdog also polls uploader_check asus_rbd_check amas_ctl_check auto_firmware_check(_merlin) awsiot_check (watchdog.c:11524-11619): ASUS phone-home paths absent from both plans.
C10|both GAP|no success metric. Define: listeners (netstat -lntu on LAN), resident daemons (ps), rootfs binaries, image bytes. Targets in §4.
C11|PR2 plan GAP|single master knob `ap_strip=1` proposed; per-daemon knobs better for bisect. Keep per-daemon; ap-harden.sh sets the set.
C12|both GAP|management-plane hardening (ssh key-only, https-only, access restriction) not tasked. Add P6.
C13|both GAP|no rule for docs drift (two plans diverged in one day). Rule E8.
C14|v2 draft gate too strict|P4 build-only validation does not need hardware; only flashing does. Gate relaxed for CI, kept for flash.
C16|research GAP|§8.5 scanned prebuilt LINK refs only; compile-time uses of flag-only identifiers in source (e.g. WAN_UNIT_IPTV) were missed. Added source #if-aware scan before each build.
C15|both plans WRONG|AMAS=n listed as final step (v1 P5.6, PR2 P3): research shows it breaks GNP build; cancelled. 7 flags (ASD MEDIASRV UUPLUGIN BWDPI IPSEC INSTANT_GUARD ALEXA+GOOGLE_ASST) break rc/httpd link via prebuilt .o refs; CONNDIAG DBLOG silently forced by AMAS; NATNL_AIHOME forced by ALEXA. v1 P4.3/P4.4 (DBLOG=n CONNDIAG=n) were no-ops.
DONE_since_v1: CI green+artifact verify (4c2f436, PR2 root fix 98fd4e0); baseline vs official (985f9b0) => only real diff MERLINUPDATE, fixed (55c9f3a), re-baselined (1011371): reproduces official up to build noise; tools/pkgtb-{unpack,compare}.sh (PR2); disable_infosvr guard (3151f6c, CI green run 40700438258).

## 2.PHASES + GATES
P0 CI reproducible+automated compare | gate: compare-official green on default branch with 0 unexplained diffs
P1 device safety+baseline (owner) | gate: recovery drill PASS, baselines committed
P2 opt-in guards, ONE build | gate: CI green, compare shows only rc/libshared changes, knobs unset => ap-diff empty vs P1 baseline
P3 on-device bisect of knobs (owner) | gate: each knob ON 24h + TESTPLAN pass, or marked KEEP
P4 compile-out tier1 (only P3-proven daemons) | gate: per batch CI+compare+TESTPLAN
P5 compile-out tier2 subsystems | gate: same; AMAS last, own gate
P6 management hardening + release discipline

## 3.TASKS
### P0
P0.1|S|15|-|DONE|upload EACCES fix: root container, docker user for clone+make|run 40698419243 green
P0.2|O|15|-|DONE|baseline vs official, MERLINUPDATE=y|docs/baseline-*.md verdict
P0.3|S|15|-|DONE|workflow: concurrency cancel, dispatch input `ref`, retention 30d, step summary sha256, paths-ignore docs/**|yaml+actionlint clean; dispatch run green
P0.4|S|20|P0.3|DONE|.github/workflows/compare-official.yml: on build success (workflow_run)+dispatch(run_id); fetch official zip, verify sha256 f6445385..., pkgtb-unpack both, pkgtb-compare, filter tools/compare-noise.txt, upload report|report artifact; "not-in-noise" list empty for unmodified build
P0.5|H|10|P0.4|DONE|compare-official on default-branch build run 40898145376 (cef17c4): beyond noise only ./sbin/rc differs (= PR3 guards). compare run 40906828698|0 unexplained diffs
P0.6|H|15|P0.5|DONE|cause: since PR2 build ran via sudo -u docker with umask 002 => CI image group-writable (2386 mode-only diffs). fix umask 022 for clone+make (b181c24); after fix only baseline class remains (official rom/etc 664/775 vs build 644/755). compare now classifies metadata diffs|run 40930588678
### P1 (owner; scripts prepared by agents)
P1.1|S|15|-|DONE(steps partly UNVERIFIED)|docs/RECOVERY.md (rescue mode, Firmware Restoration, TFTP, nvram reset, backup)|doc merged
P1.2|U|20|P1.1|TODO|recovery drill on device with OFFICIAL 3006.102.9|§5: PASS + minutes
P1.3|S|20|-|DONE(mock-tested; not on device)|tools/ap-baseline.sh ap-diff.sh ap-harden.sh (busybox, secrets redacted) + docs/TESTPLAN.md|sh -n/shellcheck clean
P1.4|U|15|P1.3|TODO|official image, AP mode, radios+GNP configured: `ap-baseline.sh official`|baseline/official/* committed
P1.5|U|15|P1.4,P0.5|TODO|flash CI build of default branch: `ap-baseline.sh ci-unmod`; `ap-diff.sh`|diff empty except buildno/version
P1.6|S|10|P1.4|TODO|docs/LISTENERS.md from baseline: port|proto|proc|needed_AP|knob|plan_ref|every listener row filled
### P2 opt-in guards (knob unset => upstream behaviour)
P2.1|S|20|-|DONE|guards A: wanduck=existing wanduck_down (watchdog.c honours via no_need_to_start_wanduck); lldpd=existing stop_amas_lldpd; NEW disable_networkmap (start+watchdog) disable_mdns (no respawn)|DONE in branch
P2.2|S|20|-|DONE|guards B: NEW disable_cfgsync (start_cfgsync+cfgsync_check) disable_conndiag (+watchdog) disable_obd (start_obd, start_eth_obd, init check_services). amas_lib: native knob disable_amas_lib in prebuilt amas_lib.o (disassembled), no code. GNP/SDN rc source has no cfg_server/amas_lib dependency; httpd falls back to local apply when cfg_server absent (web.c:27113); confirm on device|this PR
P2.3|S|20|-|DONE|guards C: NEW disable_asd disable_nt_center disable_wlc_nt; mastiff=existing aae_disable_force; dblog+awsiot not built for GT-AX6000 (FRS_FEEDBACK=n, no AWSIOT)|cd97594
P2.4|S|20|P2.1-3|DONE|guards D: NEW disable_amas_ctl (start_amas_lanctrl+amas_ctl_check, non-RE). uploader (no UPLOADER), asus_rbd (no ROUTERBOOST), auto_firmware_check (#if 0) not built. Merlin fw check: existing firmware_check_enable=0 + disable_asd=1 (watchdog SIGUSR1s asd before the enable check). Manual UI fw_check ignores knob (user-initiated, kept)|this PR
P2.5|O|15|P2.1-4|DONE|review all guards: #ifdef balance, no default change, stop_ before return, watchdog covered|review notes in PR
P2.6|S|10|P2.5|DONE|apply patches, one commit per daemon group, dispatch CI on branch|CI green
P2.7|H|10|P2.6|DONE|compare-official vs P2 build (default-branch run 40898145376, cef17c4): beyond noise only sbin/rc|compare run 40906828698
P2.8|H|10|P2.6|DONE|ap-harden.sh KNOBS list == knobs actually added (grep `nvram_match("disable_` rc/)|lists equal
### P3 on-device bisect (owner, scripts do the work)
P3.1|U|10|P1.5,P2.7|TODO|flash P2 build, knobs unset; ap-diff vs ci-unmod|empty
P3.2|U|10/knob|P3.1|TODO|per knob order: infosvr asd nt_center wlc_nt mastiff(aae) lldpd(stop_amas_lldpd) mdns networkmap conndiag wanduck amas_lib obd amas_ctl cfgsync(last: GNP risk). `ap-harden.sh apply <knob>`, reboot, TESTPLAN quick(radios, GNP VLAN, https, ssh)|per knob PASS/FAIL in §5
P3.3|U|5|P3.2|TODO|all PASS knobs on together; 24h soak; full TESTPLAN|§5 PASS
P3.4|O|10|P3.3|TODO|classify each daemon: OFF-SAFE (=>P4 candidate) | KEEP(reason)|table in §5
### P4 compile-out tier1: flag-only, no prebuilt link refs (source: docs/gt-ax6000-ap-plan.md §8.5)
gate change (C14): CI build+compare may run ahead of P3 for flags unrelated to P3 knobs; FLASH still waits for P1+P3. 1 commit per batch (flags listed in msg); CI may validate several batches in one build; device flashes <=1 batch at a time.
mechanism: append `FLAG=n` at END of `export GT-AX6000 +=` (last export wins, SR:7025) incl. base-var flags (OOKLA CONNDIAG from HND-94912_BASE)
P4.B1|S|10|-|BUILT(CI green; flash pending)|DISABLE_NETWORKMAP=y GAME_MODE=n ADGUARDDNS=n (DISABLE_NETWORKMAP: default networkmap_enable=0, ABI precondition for B4/P5.B14)|CI green; compare: no binary removed, rc/httpd changed
P4.B2|S|10|-|BUILT(CI green; flash pending)|PRINTER=n TIMEMACHINE=n NFS=n (XT12 same-SDK exemplar)|compare: u2ec LPRng netatalk nfs-utils portmap removed
P4.B3|S|10|-|BUILT(CI green; flash pending)|SNMPD=n OOKLA=n TOR=n|net-snmp ookla tor removed
P4.B4|S|10|P4.B1|BUILT(CI green; flash pending)|CAPTIVE_PORTAL=n CP_FREEWIFI=n WTFAST_V2=n (shm ABI: networkmap must not run => B1 first; WTFAST_V2 no-op)|coovachilli lighttpd samba-3.5.8 removed
P4.B5|S|10|-|BUILT(CI green; flash pending)|+fix httpd/web.c ej_httpd_cert_info brace unbalanced without LETSENCRYPT (09ad30d); LETSENCRYPT=n UPNPIGD2=n EMAIL=n|acme.sh socat miniupnpd-igdv2 removed (email stays: NC needs it)
P4.B6|S|10|-|BUILT(CI green; flash pending)|ACCEL_PPTPD=n only. MULTICASTIPTV KEPT (init-broadcom.c:11833 WAN_UNIT_IPTV unguarded); WIREGUARD KEPT (openvpn_control.h uses wg_type_t, defined only under WIREGUARD)|accel-pptpd removed
P4.B7|S|10|-|BUILT(CI green; flash pending)|NATNL_AICLOUD=n ALEXA=n INTERNETCTRL=n together (keep GOOGLE_ASST=y NATNL_AIHOME=y; TUNNEL stays)|CI green
P4.B8|S|10|-|DROPPED|OPENVPN=n VPNC=n: rc/sdn.c (GNP) calls amvpn_set_killswitch_rules(VPNDIR_PROTO_OPENVPN) unguarded (sdn.c:1124) and vpnc_* from vpnc_fusion.o (needs VPNC) under VPN_FUSION (run 40902798521). Not worth patching GNP code for size; OpenVPN never runs in AP|-
P4.9|O|15|P4.B1-8|DONE|combined P4+P5 compare reviewed: critical 26/26, new dangling 0, removals match batches|compare run 40920909282
P4.10|U|20/batch|P3.4,P4.9|TODO|flash in order B1..B8, ap-diff+TESTPLAN each|§5 PASS per batch
### P5 compile-out tier2: source patch required first (1 concern per commit; CI validates)
P5.B9|S|15|P4|BUILT(CI green; flash pending)|UUPLUGIN=n + shared/Makefile:572 link uu_utils.o unconditionally (private.o, priv_webapi.o U uu_model_check)|CI green
P5.B10|S|15|P4|BUILT(CI green; flash pending)|MEDIASRV=n + rc/usb.c #else stub find_dms_dbdir_candidate (broadcom.o U)|CI green; minidlna mt-daapd ffmpeg removed
P5.B11|S|20|P4|BUILT(CI green; flash pending)|+prn_cert_info moved out of web.c IPSEC block (httpd.c start_ssl calls it unconditionally; run 40907561586); IPSEC=n INSTANT_GUARD=n + httpd/web.c get_ipsec_remote_id gen_pre_shared_key unconditional (web_hook.o U)|CI green; strongswan removed
P5.B12|S|20|P4.B1,infosvr-gate|BUILT(CI green; flash pending)|+libasc built when TPVPN (rc links -lasc) (d91dc5c); ASD=n + stub start_asd (private.o U); networkmap gated off or LIBASC kept (networkmap NEEDED libasc.so)|CI green; asd libasd removed
P5.B13|S|20|P4.B7|BUILT(CI green; flash pending)|NATNL_AIHOME=n GOOGLE_ASST=n + aae_ipc.o unconditional (shared/Makefile:525) + wb/libws.so out of TUNNEL guard (nt_center NEEDED libws.so) + add_ifttt_flag unconditional (httpd.c:262)|CI green; aaews mastiff asusnatnl removed
P5.B14|O|20|P5.B10,P4.B1|BUILT(CI green; flash pending)|BWDPI=n + stubs check_bwdpi_nvram_setting check_tdts_module_exist get_fw_mesh_extender get_fw_user_list mesh_set_extender check_wrs_switch; networkmap gated off; then MDNS=n TIMEMACHINE=n (MEDIASRV already n) drops avahi w/o mDNSResponder|CI green; bwdpi ~6.9MB, avahi removed
P5.GATE|S|20|-|BUILT(CI green; flash pending)|NO_INFOSVR NO_NETWORKMAP package gating (patch ready p5-gate, obj-n keeps clean) + f_exists early-return in start_infosvr start_networkmap (p5-gate-rcguard; stops watchdog fork loop). keep networkmap/ dir; GUI find-ASUS (asusdiscovery) breaks|CI green; binaries absent
P5.CFG|S|15|P3 cfgsync PASS|TODO|cfg_mnt/Makefile NO_CFGSERVER=y: skip cfg_server cfg_client cfg_reportstatus gencfgcert.sh, keep libcfgmnt.so (GNP needs it; patch ready p5-cfg). MUST add f_exists("/usr/sbin/cfg_server") early-return in start_cfgsync AND cfgsync_check (else watchdog notify_rc_and_wait_2min loop + cfg_master nvram_commit on AP)|CI green; GNP OK on device
P5.AMAS|O|-|-|CANCELLED|AMAS=n breaks GNP build (§8.1): prebuilt amas_apg.o/web_hook.o need CFGSYNC/LIBASUSLOG/ACCOUNT_BINDING symbols, MULTILAN code calls AMAS-only fns. CONNDIAG DBLOG CFGSYNC NOTIFICATION_CENTER stay compiled; runtime knobs only|-
### P6 hardening + release
P6.1|U|10|P3.3|TODO|sshd key-only LAN-only, https-only (http_enable=1? verify value), disable http on WAN n/a, enable_acc_restriction w/ mgmt subnet|ap-baseline listen.txt: 22,443 only (+53/67 if dnsmasq KEEP)
P6.2|S|15|P4|DONE(untested until first tag)|.github/workflows/release.yml: on tag v3006.102.9-ap*: reuse green build of tag commit (no rebuild) + successful compare-<run_id>; gh release --prerelease 'NOT FOR USE' with pkgtb, sha256sums, compare-report|first tag publishes
P6.3|S|15|-|DONE|tools/upstream-check.sh [branch] [base]: fetch RMerl, list new commits + overlap with fork-patched files; prints NEW_COMMITS OVERLAP_COUNT VERSION_BUMP|run 2026-10-29: NEW_COMMITS=39 OVERLAP_COUNT=6 VERSION_BUMP=yes
P6.4|U+O|10|P6.3|TODO(owner decision)|evidence 2026-10-29: upstream 3006.102-wifi6 has 39 commits past c73015d incl 1e043548f9 'Bumped revision to 3006.102.10 alpha1' (contradicts PR2 note '102.10 WiFi7-only'); overlaps: httpd TLS idle stall e0470de0b3, httpd 3 mem leaks f382a51904, watchdog fw-check rate a591c3b6bb, services UDP timeouts 45a5ffd741, Makefile 957b70e0a9 d4797eccc9. RECOMMEND: stay pinned on 102.9 for P1/P3 device work (stable baseline), cherry-pick e0470de0b3+f382a51904 (httpd = only kept web-facing daemon) as a small PR after review, rebase onto 102.10 final when released (re-run P0 baseline+compare)|decision recorded
P6.5|H|10|P4|DONE|README Status updated (built, untested on hardware; links PLAN + RECOVERY); per-commit change table = PLAN §5 + PR descriptions|README current

## 3b.ARTIFACTS TO FLASH (Actions artifacts expire 30d after their run; re-dispatch build-gt-ax6000 with ref=<sha> if gone)
P1.5 unmodified-equivalent: none kept; use official image for P1.4, then P3.1 build below with all knobs unset
P3.1 guards only (no compile-out): run 40898145376 artifact gt-ax6000-cef17c4fb7500b42f88a871dffa84c95ac5191c8 (built 2026-10-29, group-write modes: pre-umask fix; re-dispatch on cef17c4 after merge of umask fix if exact modes matter)
P4.10 guards + compile-out + umask fix: default-branch build of merge 5b7edcd (PR 5) or later; check compare-official green for that run first (E10)

## 4.TARGETS (P6 exit)
listeners_LAN<=tcp22,tcp443(+udp53,udp67 iff dnsmasq KEEP); 0 ASUS cloud/discovery/mesh daemons resident; every removed binary traceable to 1 commit; TESTPLAN 100%; recovery drill PASS on record.

## 5.STATUS LOG (append-only: date|task|result|ref)
2026-10-28|P0.1|PASS|run 40698419243
2026-10-28|P0.2|PASS|1011371 (MERLINUPDATE re-baseline)
2026-10-28|infosvr guard|CI PASS|run 40700438258
2026-10-29|PR1+PR2 merged|plans consolidated into v2|3e53067
2026-10-29|P2.5 review|1 major (monitor_asd log growth) fixed, amas_lanctrl kill added|d1e78f9
2026-10-29|P2.6 CI all guards|PASS 45min|run 40890277244
2026-10-29|P4.B1-B8 P5.GATE,B9-B14|commits prepared|PR 4
2026-10-29|P0.6 umask fix|2386 group-write diffs gone; critical 26/26; dangling new 0|build 40923528833 compare 40930588678
2026-10-29|PR4 post-merge|default build 40921836403 green; compare 40928799673 green
2026-10-29|PR4 compare|critical paths 26/26 present; new dangling DT_NEEDED 0 (official baseline 1: lld2d|libbcm_crc.so); removals = strongswan bwdpi netatalk minidlna nfs chilli/lighttpd aaews/mastiff infosvr networkmap asd ookla tor pptpd; /usr/lib/libws.so gone but /lib/libws.so kept (official ships both)|run 40920909282
2026-10-29|PR4 head build P4+P5|PASS 41min; image 52,148,504 B vs 70,438,868 B (-18.3 MB, -26%)|run 40910854359
2026-10-29|P0.5 compare|PASS: only sbin/rc beyond noise|run 40906828698
2026-10-29|head build|FAIL httpd link prn_cert_info (IPSEC=n); moved out of IPSEC block|run 40907561586
2026-10-29|source scan|3 certain breaks fixed pre-build: WIREGUARD kept, web.c brace, libasc for TPVPN|6ffc07b 09ad30d d91dc5c
2026-10-29|head build|FAIL sdn.c VPNDIR_PROTO_OPENVPN (OPENVPN=n); B8 dropped|run 40902798521
2026-10-29|P4 tip build|FAIL WAN_UNIT_IPTV (MULTICASTIPTV=n); flag kept|run 40898342703, fix ffa4a2e

## 6.EXECUTION RULES
E1 one task per agent; brief=task line+file refs+done_when; agent returns diff/output+1-line result; agents never commit, push or edit PLAN.md.
E2 guards: `if (nvram_match("disable_<x>","1")) { stop_<x>(); return 0; }` inside start_<x>, and early return in matching watchdog *_check. Reuse an existing knob only if it covers all start paths AND watchdog.
E3 parallel agents editing the same C file write patches to scratchpad; orchestrator applies (git apply --check first).
E4 P4: 1 commit/batch, CI may combine batches, flash <=1 batch; P5: 1 concern/commit, stub/patch in same commit as flag; AMAS never.
E5 every flash: CI green + compare report reviewed + official image on laptop. after: ap-diff + TESTPLAN same session.
E6 commit msg `<area>: <imperative>` + evidence (file:line, removed binaries). no model ids.
E7 >20min => split in this file before continuing.
E8 docs: facts in docs/gt-ax6000-ap-plan.md, order/status here only; update both in the same PR.
E9 any PR seen => drive to merged (owner instruction 2026-10-28).
E10 no merge of a build-affecting PR unless: CI build green on head source, compare-official critical-paths pass, new dangling DT_NEEDED = 0, removed paths match intent.
E11 before each build that drops flags: #if-aware source scan for flag-only identifiers used unguarded + flag-gated functions called unguarded (C16).
