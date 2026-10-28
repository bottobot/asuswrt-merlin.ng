# Handoff: GT-AX6000 AP strip-down firmware (asuswrt-merlin fork)

> Public copy: MAC addresses, SSIDs, people's names, SSH details and security findings are
> redacted or held back. The owner keeps the full version.

Written 2026-10-28 by a netsec session (AgentBoard task 088616) for the next Claude session working in this
workspace. Read all of it before acting. Verify live state before relying on any fact here.

## The goal, in the owner's words

Strip down ASUS's firmware on the owner's GT-AX6000, which runs only as a wireless **access point** behind a
separate OPNsense firewall, so that it stops running services an AP does not need, **without breaking it**. Keep
both radios, VLAN-tagged guest networks (Guest Network Pro), the web UI and SSH administration. The owner's
stance, as stated in the fork README: he is hacking at the edges of something that is already a work of art,
and nobody should consider the result secure.

A first attempt in April 2026 failed. The owner's assessment: it was too complex and unwieldy for the models
of the time, and he believes current models can handle it. **Keep the work small and incremental: one
reviewable change at a time, each built in CI and checked before the next.** Do not repeat April's big-bang
approach (42 flags, 47 deleted directories and a 925-line patch all at once).

## Where things are

| What | Where |
|---|---|
| Source and CI | **Public** fork https://github.com/bottobot/asuswrt-merlin.ng. Nothing is cloned locally, by owner choice: develop in the cloud. |
| Default branch | `ap-stripdown` = upstream `3006.102-wifi6` at `c73015d2b494` ("Bumped revision to 3006.102.9 final", 2026-09-23), plus three commits: `f720b0a` (upstream README kept as `README-upstream.md`), `60b5f9b` (owner's README), `9c96e1f` (workflow) |
| Why that base | RMerl builds the GT-AX6000 release from the `3006.102-wifi6` branch, **not** the `3006.102.9` tag. At the tag, `release/src/router/shared/prebuild/GT-AX6000/` lacks `uu_utils.o`, so build #1 failed (`prebuild/uu_utils.o: No such file or directory`, with `UUPLUGIN=y`). The wifi6 branch has it. |
| Workflow | `.github/workflows/build-gt-ax6000.yml` (copy in `reference/`). It runs on pushes to `ap-stripdown` except `**.md`, or manually. It uses the `gnuton/asuswrt-merlin-toolchains-docker:latest` container (user `docker`, runner `/mnt` mounted at `/project`), runs `source /home/docker/envs/bcm-hnd-ax-4.19.sh`, then `make gt-ax6000` in `release/src-rt-5.04axhnd.675x`. It uploads `*_nand_squashfs.pkgtb` plus `sha256sums.txt`, and always uploads `build.log`. |
| CI runs | #1 `40638795392`: failure (wrong base, see above). #2 `40640600800`: **was still running at hand-off**; check it first: `gh run view 40640600800 -R bottobot/asuswrt-merlin.ng`. |
| Get a build | `gh run download <run-id> -R bottobot/asuswrt-merlin.ng -D /var/tmp/merlin-fork/run-<id>/` (keep downloads in `/var/tmp`, never `/tmp`) |
| Official 102.9 image | `/var/tmp/asus-fw-3006.102.9/GT-AX6000_3006_102.9_0_nand_squashfs.pkgtb`, sha256 `f64453852fb3eacb996978cc2c0abc505e744c7a9a3a4522f0a98866e2c7a7e0`, which matches both the bundled sha256 file and asuswrt-merlin.net |
| April design docs | Only `docs/april-2026/2026-04-15-merlin-build-system-investigation.md` is in this repo. The other April docs stay with the owner until a private disclosure route exists for their security findings. |
| AP-mode bug report | `docs/2026-10-28-bug-report-ap-mode-guest-network.md`: the stale VLAN 52 Guest Network Pro subnet (dnsmasq FAILED on `192.168.52.1`), the guest VLAN on every LAN port, the 102.9 bridge migration, three-layer isolation, and driver-noise baseline (session 3b694e) |
| Router NAND backup | `/home/robert/Dev Stuff/netsec/scans/asus-router-20260411/full-nand-dump.img` (full 256 MB flash, 2026-04-11) |

## What April learned (still valid; details in `docs/april-2026/2026-04-15-merlin-build-system-investigation.md`)

- Feature flags live **only** in `release/src-rt-5.04axhnd.675x/target.mak` (GT-AX6000 is `export GT-AX6000 := $(HND-94912_BASE)` plus `+=` lines). `config_gt-ax6000`, `.config` and `rtconfig.h` are regenerated every build by the `RouterOptions` function in the SDK `Makefile`, so never edit them.
- Parent flags auto-enable children (e.g. `CONNDIAG` → LIB_CODB/DNS_PING; `AMAS` → CFGSYNC/DWB/WLCEVENTD/…; `CAPTIVE_PORTAL` → COOVACHILLI). Disable the parent. Override inherited `HND-94912_BASE` flags in the GT-AX6000 line rather than editing the base.
- Some code is linked from prebuilt objects in `release/src/router/shared/prebuild/GT-AX6000/` when its `.c` file is absent, so disabling a flag may be the only way to drop that code.
- Known source bug: `release/src/router/httpd/sysinfo.c` includes `openvpn_config.h` without an `#ifdef RTCONFIG_OPENVPN` guard, so disabling OpenVPN breaks the build until the include is guarded.
- `PROXYSTA` should stay enabled; disabling it caused `lan.c` syntax errors.
- Security patches April still considered necessary after stripping (re-implement them; the patch file is lost):
  #1 an nvram guard `disable_infosvr` in `start_infosvr()` (rc/services.c) and `infosvr_check()` (rc/watchdog.c).
  Line numbers in the April docs are from 102.7 and have moved. The other April security findings are held back
  from this public repo until a private disclosure route exists; ask the owner.
- RMerl closed the April upstream PRs and asked for private disclosure instead, so never open upstream PRs or
  public issues for security findings.

## The live router (production: do not experiment on it)

- GT-AX6000 at `192.168.2.174`, AP mode (`sw_mode=3`), Merlin **3006.102.9** flashed by the owner on 2026-10-26.
  SSH: `ssh-with-purpose asus "<purpose>" 'sh -s' < script.sh`. **Every connection costs the owner a YubiKey touch**, so batch reads, conditional fixes and verification into one script, and confirm the owner is present and the key is plugged in first.
- Router syslog is shipped to Loki (`http://10.100.0.1:3100`, label `{host="gt-ax6000"}`), so most checks need no touch.
- Listening services that motivate this project, seen open on `192.168.2.174` from VLAN 2 before the 10-26 hardening: infosvr 9999/udp, wanduck 18017/tcp and 18018/udp, cfg_server (AiMesh) 7788, avahi 5353. Today a `/jffs/scripts/firewall-start` HARDENING iptables chain drops these at runtime (loaded from `services-start` because `firewall-start` never fires in AP mode). Firmware-level removal is this project's goal.
- `/jffs` customisations that a custom build must keep working: `services-start`, `service-event-end`, `firewall-start` (HARDENING), `vlan30-uplink.sh` (3-layer guest isolation), `guest-iso-watch.sh` (15-minute isolation logger, cru `GuestIsoWatch`), and `init-start` (syslog to `192.168.2.1:514`).
- Guest network **GUEST-SSID** = VLAN 30 (`vlan_rl=<1>30>0>`, bridge `br30`). Isolation needs three layers: `wl ap_isolate`, **`dhd ap_isolate`** (the radios are offload dongles), and br30 port `isolated`. The 102.9 upgrade broke the bridge layout once (fixed). Deleting and recreating the guest profile lands on a stale **VLAN 52** template, and the creation dialog has no VLAN field: edit the profile afterwards and set the VID to 30, applying once. Owner rule: the guest profile is managed through the UI only.
- Open investigation (the netsec workspace owns it): acsd flips the 2.4 GHz chanspec between 20 and 40 MHz about every 15 minutes, which probably resets `dhd ap_isolate` on `wl0.1`. Candidate fix: fixed 20 MHz on 2.4 GHz.

## Hard constraints

- **Never build firmware locally on lilguy** (14 GB RAM, history of OOM crashes). Builds run in GitHub Actions. theMeg (WSL2 + Docker) is the only acceptable local fallback, and only on request.
- **Never flash a custom build onto the household AP.** Full-image testing needs a second GT-AX6000 test router (not yet bought). Until then, testing means: (1) unpack and compare images offline, and (2) run a single rebuilt binary from `/tmp` on the live router, which a reboot undoes, with the owner's approval.
- The fork is **public**: never commit secrets, PSKs, nvram dumps or anything from `/jffs` that contains credentials.
- Recovery: ASUS rescue mode plus the official 102.9 image above; last resort, the NAND dump.
- Machine rules live in `~/.claude/CLAUDE.md` and the netsec `CLAUDE.md` (agent caps, Haiku-for-fetch, bounded regexes, YubiKey batching). They apply here too.

## Suggested next steps

1. Check run #2. If it failed, read the log with `gh run view <id> --log-failed`, fix the workflow and push. Consider pinning the container image by digest once a build is green.
2. Baseline: unpack the CI image and the official image (the `.pkgtb` is a FIT image; try `dumpimage -l`, or binwalk with ubi_reader/unsquashfs), then diff the rootfs file lists and sizes. Expect timestamp-only differences. Record the result in this workspace.
3. First real change: one small, low-risk strip, e.g. the `disable_infosvr` nvram guard (patch #1) or one leaf feature flag. Build, diff against the baseline, and confirm the binary or service is gone.
4. Plan a test router before any full-image flash.
5. Optionally turn this workspace into a git repo for notes and diff results.

## Provenance

- The netsec session's handoff for the router work: `/home/robert/Dev Stuff/netsec/docs/handoff-20261026-vlan30-scope.md` (branch `task/088616`, commit `0a1b317` and later edits).
- Memory: `~/.claude/projects/-home-robert-Dev-Stuff-netsec/memory/project_router_hardening.md` and `project_quarantine_vlan30.md`. A new session started in this workspace gets a different memory folder, so read those files directly.
