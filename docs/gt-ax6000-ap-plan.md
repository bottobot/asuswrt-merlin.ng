# GT-AX6000 AP strip-down: investigation+plan (2026-10-28)
fmt: machine-readable; k=v; refs=file:line under release/src/router unless prefixed

## 0.target
model=GT-AX6000 soc=BCM4912 sdk=release/src-rt-5.04axhnd.675x kernel=4.19 toolchain=aarch64-gcc-9.2-glibc-2.30
target_entry=src-rt/target.mak:197-221 (HND-94912_BASE + GT-AX6000); make_target=gt-ax6000 (BUILD_NAME=upcase goal, src-rt/Makefile:88)
image=image/GT-AX6000_3006_102.9_0_nand_squashfs.pkgtb (u-boot FIT: img0=bootfs 10.4MB multi-file, img1=nand_squashfs rootfs 56.8MB xz squashfs 3940 inodes; cfg=conf_4912_a0+_nand_squashfs)
baseline=Merlin 3006.102.9 (branch 3006.102-wifi6 @c73015d; version.conf SERIALNO=102.9 EXTENDNO=0); asus_gpl_base=3.0.0.6.102_37538 (merged 102.8; no new GPL in 102.9)
official_sha256=f64453852fb3eacb996978cc2c0abc505e744c7a9a3a4522f0a98866e2c7a7e0 (verified from sourceforge zip 2026-10-28; matches asuswrt-merlin.net)
use_case=sw_mode=3 re_mode=0 wlc_psta=0 (pure AP; access_point_mode() shared/shared.h:2074 does NOT exclude re_mode=1 -> keep re_mode=0)
keep=radios, Guest Network Pro VLAN, httpd/https, dropbear
no_loader_needed: no documented min stock fw/bootloader for 3006.102.x on GT-AX6000; tree builds no loader for this model

## 1.repo_state
branches: ap-stripdown(default)=upstream+README+CI; main=upstream mirror; claude/great-dirac-e98rgz=this work
ci=.github/workflows/build-gt-ax6000.yml (gnuton container, /mnt->/project, make gt-ax6000)
ci_runs: #1 fail; #2 (9c96e1f) build OK 63min, image 70438876B sha256=072db7cf...882f6, artifacts uploaded (id 12798202289 fw, 12797389280 log) BUT job marked failed: EACCES /__w/_temp/_runner_file_commands/set_output_* (runner creates per-step files as host uid; container runs --user docker; chmod in step3 does not cover later-created files)
ci_fix=container --user root (runner per-step files need root) + sudo -u docker for clone and make (SDK make.common:3470 prebuild_checks refuses root). VERIFIED run 40684815903 @98fd4e0: success, build 42min, artifacts gt-ax6000-<sha> (66.8MB zip) + build-log-<sha>. Merged with ap-stripdown 55c9f3a: image pinned by digest, MERLINUPDATE=y, artifact verify step
baseline_done=docs/baseline-3006.102.9-ci-vs-official.md (CI 9c96e1f vs official): only real diff = CI lacked MERLINUPDATE=y (ASUS webs_update.sh vs Merlin's); rest = timestamps, build path, mode, locale noise
ci_disk: /project 145G, 80G used after build; / not used
ci_vs_official_size: 70438876 vs 70438392 (+484B); expect diffs only in timestamps/FIT metadata; verify with tools/pkgtb-compare.sh
local_tree_size: src-rt-5.04axhnd.675x=1.8G src=2.3G

## 2.tooling
### 2.1 cloud session (this env) status
os=Ubuntu24.04 cpu=4 ram=15G disk_avail=21G(after apt) root=yes apt=OK pip=OK docker_daemon=NO(binary only)
installed_now: u-boot-tools(dumpimage) squashfs-tools(unsquashfs) binwalk flex gperf libtool-bin gettext fakeroot
net: sourceforge OK; github OK; *.blob.core.windows.net (Actions artifact download) BLOCKED 403 via proxy; snbforums/asuswrt-merlin.net/nvd/asus.com unreachable by WebFetch (search snippets only)
cannot: run full firmware build here (no cross toolchain am-toolchains ~GB, 21G disk insufficient for 80G build, no docker). Build stays in GitHub Actions.
can: source edits, target.mak/config reasoning, unpack+diff official vs CI image, grep rootfs, write/validate scripts, read CI logs via github MCP
### 2.2 tools added
tools/pkgtb-unpack.sh <img> <out>: dumpimage -l; extract img0 bootfs.bin, img1 rootfs.sqsh; unsquashfs; manifest.tsv(path,type,mode,size,link) sha256.txt image-hashes.txt (tested on official image: 3939 entries, 3097 files)
tools/pkgtb-compare.sh <dirA> <dirB>: only-in-A/B, content diff, metadata diff
### 2.3 needed next
- CI step: after build, download official 102.9 zip from sourceforge, run unpack+compare, upload report as artifact (works around blob-storage block in cloud session; CI runner can fetch sourceforge)
- CI: cache nothing (tree is 4G+; build 63min fits 6h); add workflow_dispatch input for ref; add concurrency cancel-in-progress
- optional: device-tree-compiler (fdtget/dtc) to dump FIT ITS; ashway83/asuswrt-fwtool for rebuild/overlay (not needed if building from source)
- hw test loop (user side): serial console (UART on GT-AX6000 board), TFTP/recovery via u-boot (ASUS Firmware Restoration), second GT-AX6000 or accept brick risk; capture `netstat -lnp`, `ps`, `nvram get sw_mode` baseline from stock Merlin in AP mode BEFORE strip
- docker image staleness: gnuton/asuswrt-merlin-toolchains-docker:latest == tag 20250107 (Jan 2025, Ubuntu20.04, am-toolchains cloned at image build). Mitigation: pin tag 20250107; if am-toolchains needs newer, build own image FROM it + git -C /home/docker/am-toolchains pull
- gotcha: stale chip_profile.tmp from other target breaks make gt-ax6000 (clean tree per build; CI clones fresh so OK)
- env script typo: envs/bcm-hnd-ax-4.19.sh references $LD_LIBRARY (harmless)

## 3.service_inventory (AP mode, sw_mode=3 re_mode=0)
cols: daemon|port|start_ref|gate_in_AP|flag(target.mak var->RTCONFIG)|src_or_prebuilt|runtime_knob|watchdog_respawn|action
- infosvr|udp9999|services.c:4602 (<-12661)|runs (skip only AP+modem_bridge)|none, obj-y Makefile:1736|src except prebuild/GT-AX6000/interface.o|none|yes watchdog.c:11119|STRIP: compile out obj-y + guard start_infosvr + infosvr_check (cf RMerl PR #886 pattern disable_infosvr nvram)
- wanduck|tcp18017 udp18018|lan.c:2585 (WEB_REDIRECT)|runs; AP skip in no_need_to_start_wanduck is #if 0 services.c:13662|none; in rc rc/Makefile:552|src rc/wanduck.c|wanduck_down=1 services.c:13683|yes watchdog.c:11211|STRIP: re-enable AP skip in no_need_to_start_wanduck (verify no AP-mode web redirect dependency: lan.c WEB_REDIRECT path, captive "no internet" page)
- cfg_server|tcp/udp7788|services.c:24735 start_cfgsync (<-12875, lan.c:4718)|runs when AP && x_Setting=1 && cfg_group empty|AMAS=y->RTCONFIG_CFGSYNC (src-rt/Makefile:3928)|PREBUILT cfg_mnt/prebuild/GT-AX6000/*|none|yes watchdog.c:9843 cfgsync_check|STRIP: guard start_cfgsync+cfgsync_check for pure AP; or AMAS=n (big: also drops DBLOG CONNDIAG NOTIFICATION_CENTER, lldpd, amas-utils; UI impact unknown -> test)
- cfg_client|-|services.c:12700|only re_mode=1|RTCONFIG_CFGSYNC|prebuilt|-|-|NOOP
- conn_diag+amas_ssd_cd|-|services.c:24901 (<-12877)|runs|CONNDIAG=y (forced by AMAS src-rt/Makefile:4170)|PREBUILT rc/prebuild/GT-AX6000/conn_diag*.o|none|yes watchdog.c:9867|STRIP: CONNDIAG=n or guard
- amas_lib|-|services.c:12909 start_amas_lib|unknown (prebuilt .o)|AMAS|PREBUILT rc/prebuild/GT-AX6000/amas_lib.o|none|?|STRIP via guard; test
- obd/eth_obd (onboarding)|-|services.c:12723,12729|runs|AMAS/ETHOBD|PREBUILT obd*.o|none|?|STRIP via guard
- lldpd|udp? L2 LLDP|services.c:21920 (<-12895)|runs|AMAS; obj-y Makefile:1302|src lldpd-0.9.8|stop_amas_lldpd=1 services.c:21977|?|PHASE1: nvram knob; PHASE2 compile out
- avahi-daemon|udp5353|services.c:8014 start_mdns (<-12596)|runs|MDNS=y->RTCONFIG_MDNS (src-rt/Makefile:1834); MDNS=n+TIMEMACHINE=n => mDNSResponder built if MEDIA_SERVER||BWDPI (Makefile:1596-1606)|src|none|?|STRIP: MDNS=n TIMEMACHINE=n MEDIASRV=n BWDPI=n together, else mDNSResponder replaces it
- networkmap+asusdiscovery+arpstorm+find_cap|-|services.c:4445 (<-12744, lan_up)|runs (routing check commented services.c:4450)|obj-y Makefile:1731; networkmap_enable=0 honoured only with DISABLE_NETWORKMAP=y (services.c:4453, src-rt/Makefile:3670)|PREBUILT networkmap/prebuild/GT-AX6000/*|networkmap_enable (needs flag)|yes watchdog.c:7888|PHASE1: add DISABLE_NETWORKMAP=y to target + nvram networkmap_enable=0 (UI client list breaks; acceptable for AP)
- asd|-|services.c:6548 (<-12544)|runs|ASD=y->RTCONFIG_ASD (+LIBASC) src-rt/Makefile:2099|PREBUILT asd/prebuild/GT-AX6000/{asd,libasd.so}|none|SIGUSR1 watchdog.c:11953|STRIP: ASD=n (asd=ASUS "security daemon" phoning home for signature updates)
- ahs|-|services.c:6528|NOT BUILT (AHS=n target.mak:216)|-|prebuilt exists unused|-|-|NOOP
- nt_center/nt_monitor|-|services.c:12335 (<-12550)|runs (skip only mediabridge)|NOTIFICATION_CENTER forced by BWDPI(3064) and AMAS(4110)|PREBUILT nt_center/prebuild/GT-AX6000/*; libnt.so prebuilt; rc nt_mail.o prebuilt|none|?|STRIP only if both BWDPI=n and AMAS=n; else guard start
- wlc_nt/wlc_monitor|-|services.c:4263,4296 (<-12572)|runs|NOTIFICATION_CENTER|PREBUILT|none|?|same as nt_center
- protect_srv|-|services.c:12371 (<-12553)|runs|RTCONFIG_PROTECTION_SERVER=y config_base:461|PREBUILT|none|?|EVAL: brute-force lockout for httpd/ssh; probably KEEP
- mastiff/aaews/aaeuac|outbound tunnel|natnl_api.c:105 (<-services.c:12767, usb.c:4271, rc.c:1728)|runs unless aae_disable_force=1|RTCONFIG_TUNNEL forced by NATNL_AICLOUD/NATNL_AIHOME/ALEXA=y (src-rt/Makefile:3449-3526)|PREBUILT aaews/prebuild/GT-AX6000/*|aae_disable_force=1 (Merlin UI Tools>Other "Disable Asusnat tunnel")|yes watchdog.c:11568|PHASE1 nvram; PHASE2 NATNL_AICLOUD=n NATNL_AIHOME=n ALEXA=n GOOGLE_ASST=n
- bwdpi (dcd,wred,tdts*.ko,bwdpi_check,hour_monitor)|-|services.c:12779-12780; engine only from wan_up wan.c:4577|engine NOT started (no wan_up in AP); hour_monitor needs router mode; bwdpi_check prebuilt gating unknown|BWDPI=y|PREBUILT bwdpi_source/prebuild/GT-AX6000/*|wrs_protect_enable,bwdpi_db_enable,TM_EULA default 0|watchdog.c:3061|STRIP: BWDPI=n (removes TrendMicro kmods+AiProtection+QoS UI; AP does not use). Risk: build breakage in UI/other RTCONFIG_BWDPI ifdefs -> test
- pctime|-|services.c:1205|skipped (!is_router_mode)|CONNTRACK|src|-|-|NOOP
- u2ec/lpd|tcp3394/515|usb.c:1314 (printer hotplug)|only on printer plug|PRINTER=y|u2ec PREBUILT; LPRng src|-|-|PRINTER=n (also drops lpd); low priority
- ntpd|udp123 listen only if ntpd_enable|services.c:7603 (<-lan.c:4592)|runs as client when AP has gw|NTPD=y|src|ntpd_enable(server part)|daily restart|KEEP client; ensure ntpd_enable=0
- httpd/httpds|80/443|services.c:6946|runs|always; HTTPS=y|src + prebuilt web-broadcom*.o web_hook.o pwenc.o|http_enable misc_http_x|yes watchdog.c:11488|KEEP; set https-only
- dropbear|22|ssh.c:41|runs if sshd_enable|SSH=y|src|sshd_enable|-|KEEP LAN-only
- crond|-|services.c:14330|runs|CROND|busybox|-|-|KEEP
- samba/vsftpd/minidlna|445/21/8200|usb.c:4764 hotplug; services.c:12799|on USB|SAMBASRV/FTP(vsftpd always built)/MEDIASRV=y|src|enable_samba=1 default! enable_ftp=0 dms_enable=0 usb_enable|-|PHASE1 enable_samba=0 usb_enable=0; PHASE2 MEDIASRV=n TIMEMACHINE=n (USB=n too big, affects hotplug infra)
- ledg/antled|-|services.c:14526|runs|GTAX6000 ifdef|PREBUILT ledg.o antled.o|AllLED|-|KEEP (LED control); RGBLED=n already
- telnetd|23|services.c|telnetd_enable|-|busybox|telnetd_enable=0|-|ensure 0
- dnsmasq|53/67|services.c|runs (AP: dhcp relay off)|-|src|-|-|KEEP (needed for lan? in AP mode dnsmasq serves nothing; EVAL later)
- lltd|-|services.c|runs|-|prebuilt lltd.arm|-|-|low prio
- netool|-|services.c:12556|runs|NETOOL=y|?|-|-|NETOOL=n
- sysstate/dblog/erp_monitor|-|services.c:12883 etc|runs|SYSSTATE DBLOG(forced AMAS)|prebuilt?|-|-|PHASE2
- snmpd|161|services.c|snmpd_enable|SNMPD=y|src|snmpd_enable=0|-|SNMPD=n
- tor/openvpn/wireguard/ipsec/vpnc|-|-|not started in AP by default|TOR OPENVPN WIREGUARD IPSEC VPNC|src|-|-|PHASE2 set =n to shrink image+attack surface (verify UI build ok)
- captive portal/freewifi|-|-|-|CAPTIVE_PORTAL CP_FREEWIFI|?|-|-|=n
- uuplugin/wtfast/adguarddns/instant_guard/internetctrl/game_mode|-|-|-|UUPLUGIN WTFAST_V2 ADGUARDDNS INSTANT_GUARD INTERNETCTRL GAME_MODE|prebuilt|-|-|=n PHASE2
global_knob: no_service=1 skips all start_services (services.c:12519) [debug only]
watchdog_respawn_summary: watchdog.c:11487-11652 restarts infosvr networkmap conn_diag cfg_server mastiff httpd wanduck -> jffs services-start killall is NOT sufficient; need source guards

## 4.upstream_status+known_issues
latest_stable=3006.102.9 (2026-09-23); 3006.102.10=alpha, WiFi7-only (no GT-AX6000); RMerl GitHub issues DISABLED (support via SNB)
threads: release https://www.snbforums.com/threads/asuswrt-merlin-3006-102-9-is-now-available.97950/ beta .97909 alpha .97788
102.9_changes_relevant: OpenSSL3.5 + 1.1.1 shim for closed binaries (prebuilt daemons above link via shim -> any strip must keep libssl shim libs); HW AQM QoS (router-only, irrelevant AP); B53 spectre mitigation skipped (kernel)
gt-ax6000_reports_102.9 (anecdotal, unverified): busybox ip bus error; AiMesh link to RT-AC86U lost; LEDs/AURA re-enable after Apply; OpenVPN server needs DH>=2048 under OpenSSL3.5; EEE latency (RMerlin: WiFi7 only); DNS Privacy UI missing
gnp_issues_history (relevant to keep-list): AP Isolated on GNP profile blocks 2.4<->5/wired (102.8); GNP enable broke 2.4GHz (102.6); iptables-restore intermittent fail at boot w/ GNP/SDN on 102.8_4 [UNVERIFIED]; RMerlin: guest isolation impossible in AP mode by design; old: no Guest wifi menu in AP mode .87921; cannot enable 2.4GHz .84581; mastiff crash loop after factory reset (Jan 2026)
asus_stock_latest: 3.0.0.6.102_37436 (2026-05-05); 37437 (2026-10-20) [UNVERIFIED]

## 5.security_background
infosvr: CVE-2014-9583 unauth LAN RCE (fixed 376.49_5), still listens; no disable knob upstream; RMerl PR #886 (bottobot, closed unmerged) adds disable_infosvr/disable_awsiot nvram guards in services.c+watchdog.c -> reuse that diff
cfg_server 7788: CVE-2022-38393 DoS, CVE-2023-35087 fmt string; no 2025/26 CVE found
aicloud: CVE-2025-2492 fixed 3004.388.9_2; AiCloud REMOVED in 3006.102.7 -> not present in 102.9 (NATNL_AICLOUD=y still forces TUNNEL build)
ayysshush botnet (2025): brute force + CVE-2023-39780 + persistence via SSH on 53282 w/ nvram key; mitigations: already-fixed vulns, factory reset clears nvram key; keep sshd LAN-only, key-only
merlin_cve_policy: "Merged with GPL x" implies ASUS fixes; no explicit CVE list
no_existing_AP_strip_project found; SNB kill-script threads (.83353) confirm watchdog respawn problem

## 6.plan
P0 verify_baseline (CI only)
 1. DONE CI root fix verified green
 2. DONE manual baseline diff (docs/baseline-3006.102.9-ci-vs-official.md); MERLINUPDATE=y applied. TODO automate as CI step with tools/pkgtb-unpack.sh + tools/pkgtb-compare.sh against official zip; re-baseline once with MERLINUPDATE=y build
 3. user: flash CI-built unmodified image on test unit in AP mode; capture ps/netstat/nvram baseline -> docs/baseline-ap.txt
P1 nvram-only hardening (no code change; reversible; validates assumptions)
 aae_disable_force=1 wanduck_down=1 stop_amas_lldpd=1 enable_samba=0 usb_enable=0 ntpd_enable=0 telnetd_enable=0 snmpd_enable=0 sshd_enable=1(lan) firmware_check_enable=0
 expected still running: infosvr cfg_server conn_diag networkmap asd nt_center wlc_nt protect_srv avahi amas_lib obd
P2 source guards (rc only; pattern = PR #886): nvram ap_strip=1 => skip in start_services + watchdog *_check: infosvr cfg_server/cfgsync conn_diag amas_lib obd networkmap asd nt_center wlc_nt mdns; keep protect_srv
 verify each: build green; AP boots; GNP VLANs+both radios+httpd+ssh OK; netstat shows only 22/80/443(+53/67 if dnsmasq kept)
P3 compile-out (target.mak GT-AX6000 entry): ASD=n CONNDIAG=n BWDPI=n MDNS=n TIMEMACHINE=n MEDIASRV=n NATNL_AICLOUD=n NATNL_AIHOME=n ALEXA=n GOOGLE_ASST=n NETOOL=n SNMPD=n PRINTER=n UUPLUGIN=n WTFAST_V2=n CAPTIVE_PORTAL=n CP_FREEWIFI=n; add DISABLE_NETWORKMAP=y; one flag per commit; CI each; AMAS=n LAST (largest blast radius: forces off DBLOG CFGSYNC CONNDIAG NOTIFICATION_CENTER; may break GNP/SDN UI which shares cfg_mnt libs -> test on device)
 infosvr: remove obj-y Makefile:1736 + guards (no RTCONFIG flag exists; add RTCONFIG_INFOSVR=n local flag)
P4 image diff per commit: tools/pkgtb-compare.sh prev vs new -> every removed binary traceable to a commit

## 7.open_questions
- does Guest Network Pro (SDN/MTLANCFG) in AP mode depend on cfg_mnt/libcfgmnt.so or amas_lib? (grep sdn/mtlancfg for cfg_ deps before AMAS=n)
- bwdpi_check prebuilt: does it start dcd/wred in AP mode? need device ps baseline
- amas_lib.o prebuilt: what it does on a non-mesh AP; safe to skip?
- WEB_REDIRECT/wanduck in AP: does disabling break the "router not connected" splash or GNP captive? test
- OpenSSL1.1.1 shim libs: which prebuilt daemons link them (ldd on rootfs) -> keep shim if any kept daemon needs it
- CI artifact download blocked in cloud session (blob.core.windows.net 403): need network allowlist change or push compare report into a git branch/release instead
