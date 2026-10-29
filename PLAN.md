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
P0.3|S|15|-|WIP|workflow: concurrency cancel, dispatch input `ref`, retention 30d, step summary sha256, paths-ignore docs/**|yaml+actionlint clean; dispatch run green
P0.4|S|20|P0.3|WIP|.github/workflows/compare-official.yml: on build success (workflow_run)+dispatch(run_id); fetch official zip, verify sha256 f6445385..., pkgtb-unpack both, pkgtb-compare, filter tools/compare-noise.txt, upload report|report artifact; "not-in-noise" list empty for unmodified build
P0.5|H|10|P0.4|TODO|run compare-official on run 40886333807 (PR2 merge build)|0 unexplained diffs recorded in §5
### P1 (owner; scripts prepared by agents)
P1.1|S|15|-|WIP|docs/RECOVERY.md (rescue mode, Firmware Restoration, TFTP, nvram reset, backup)|doc merged
P1.2|U|20|P1.1|TODO|recovery drill on device with OFFICIAL 3006.102.9|§5: PASS + minutes
P1.3|S|20|-|WIP|tools/ap-baseline.sh ap-diff.sh ap-harden.sh (busybox, secrets redacted) + docs/TESTPLAN.md|sh -n/shellcheck clean
P1.4|U|15|P1.3|TODO|official image, AP mode, radios+GNP configured: `ap-baseline.sh official`|baseline/official/* committed
P1.5|U|15|P1.4,P0.5|TODO|flash CI build of default branch: `ap-baseline.sh ci-unmod`; `ap-diff.sh`|diff empty except buildno/version
P1.6|S|10|P1.4|TODO|docs/LISTENERS.md from baseline: port|proto|proc|needed_AP|knob|plan_ref|every listener row filled
### P2 opt-in guards (knob unset => upstream behaviour)
P2.1|S|20|-|WIP|guards A: wanduck(existing wanduck_down if watchdog honours) networkmap mdns lldpd|patch applies; start_+watchdog both guarded
P2.2|S|20|-|WIP|guards B: disable_cfgsync(cfg_server+cfg_client) disable_conndiag disable_amas_lib disable_obd|same
P2.3|S|20|-|WIP|guards C: disable_asd disable_nt_center disable_wlc_nt disable_dblog disable_awsiot; mastiff via existing aae_disable_force|same
P2.4|S|20|P2.1-3|TODO|guards D: uploader asus_rbd amas_ctl auto_firmware_check (C9). research start paths first; split if >20min|same
P2.5|O|15|P2.1-4|TODO|review all guards: #ifdef balance, no default change, stop_ before return, watchdog covered|review notes in PR
P2.6|S|10|P2.5|TODO|apply patches, one commit per daemon group, dispatch CI on branch|CI green
P2.7|H|10|P2.6|TODO|compare-official vs P2 build: only sbin/rc + libshared differ beyond noise|recorded
P2.8|H|10|P2.6|TODO|ap-harden.sh KNOBS list == knobs actually added (grep `nvram_match("disable_` rc/)|lists equal
### P3 on-device bisect (owner, scripts do the work)
P3.1|U|10|P1.5,P2.7|TODO|flash P2 build, knobs unset; ap-diff vs ci-unmod|empty
P3.2|U|10/knob|P3.1|TODO|per knob order: infosvr asd awsiot nt_center wlc_nt dblog mastiff(aae) lldpd mdns networkmap conndiag wanduck amas_lib obd cfgsync(last: GNP risk). `ap-harden.sh apply <knob>`, reboot, TESTPLAN quick(radios, GNP VLAN, https, ssh)|per knob PASS/FAIL in §5
P3.3|U|5|P3.2|TODO|all PASS knobs on together; 24h soak; full TESTPLAN|§5 PASS
P3.4|O|10|P3.3|TODO|classify each daemon: OFF-SAFE (=>P4 candidate) | KEEP(reason)|table in §5
### P4 compile-out tier1 (flags from research; max 3 flags/build; 1 commit/flag; never ahead of P3.4 OFF-SAFE)
P4.0|S|20|-|WIP|flag dependency+link-risk map (forces/forced_by/prebuilt/.o refs) => batch order below|table in docs/gt-ax6000-ap-plan.md §8
P4.x|S|20/batch|P3.4|TODO|<filled from P4.0>|CI green, compare shows only expected removals, TESTPLAN pass
### P5 compile-out tier2 (one subsystem per build)
P5.x|S|20|P4|TODO|<filled from P4.0>|same
P5.AMAS|O|20|P5.*|TODO|AMAS=n experiment gate; precondition research verdict on GNP dependency|decision in §5
### P6 hardening + release
P6.1|U|10|P3.3|TODO|sshd key-only LAN-only, https-only (http_enable=1? verify value), disable http on WAN n/a, enable_acc_restriction w/ mgmt subnet|ap-baseline listen.txt: 22,443 only (+53/67 if dnsmasq KEEP)
P6.2|S|15|P4|TODO|CI on tag v3006.102.9-apN: build+compare, GitHub pre-release "not for use", attach pkgtb+sha256+report|tag release works
P6.3|S|15|-|TODO|tools/upstream-check.sh: new RMerl 3006.102-wifi6 commits touching files we patch|script output
P6.4|O|10|P6.3|TODO|policy: stay pinned 102.9 (102.10 is WiFi7-only) vs rebase per point release|decision
P6.5|H|10|P4|TODO|README Status <- link §5; CHANGES table sha|area|removed|listener_delta|committed

## 4.TARGETS (P6 exit)
listeners_LAN<=tcp22,tcp443(+udp53,udp67 iff dnsmasq KEEP); 0 ASUS cloud/discovery/mesh daemons resident; every removed binary traceable to 1 commit; TESTPLAN 100%; recovery drill PASS on record.

## 5.STATUS LOG (append-only: date|task|result|ref)
2026-10-28|P0.1|PASS|run 40698419243
2026-10-28|P0.2|PASS|1011371 (MERLINUPDATE re-baseline)
2026-10-28|infosvr guard|CI PASS|run 40700438258
2026-10-29|PR1+PR2 merged|plans consolidated into v2|3e53067

## 6.EXECUTION RULES
E1 one task per agent; brief=task line+file refs+done_when; agent returns diff/output+1-line result; agents never commit, push or edit PLAN.md.
E2 guards: `if (nvram_match("disable_<x>","1")) { stop_<x>(); return 0; }` inside start_<x>, and early return in matching watchdog *_check. Reuse an existing knob only if it covers all start paths AND watchdog.
E3 parallel agents editing the same C file write patches to scratchpad; orchestrator applies (git apply --check first).
E4 max 3 flags/build (P4); P5 one subsystem/build; AMAS alone.
E5 every flash: CI green + compare report reviewed + official image on laptop. after: ap-diff + TESTPLAN same session.
E6 commit msg `<area>: <imperative>` + evidence (file:line, removed binaries). no model ids.
E7 >20min => split in this file before continuing.
E8 docs: facts in docs/gt-ax6000-ap-plan.md, order/status here only; update both in the same PR.
E9 any PR seen => drive to merged (owner instruction 2026-10-28).
