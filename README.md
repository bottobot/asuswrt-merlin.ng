# asuswrt-merlin.ng: a strip-down for the GT-AX6000 in access-point mode

> **⚠️ Experimental. Not tested on hardware yet. Do not run this on a network you depend on.**
> This is one person's hardening experiment. Nothing here has been audited or is supported,
> and any build from this repository may break your device, weaken its security, or both.
> For a well-maintained firmware, use the official
> [Asuswrt-Merlin](https://github.com/RMerl/asuswrt-merlin.ng) releases.

## What this is

An independent project built on [Asuswrt-Merlin](https://www.asuswrt-merlin.net/), narrowed to
one job: a GT-AX6000 used **only as a wireless access point** behind a separate firewall.

I have huge respect for the amount of work Eric Sauvageau (RMerl) and the Merlin contributors
have put into Asuswrt-Merlin over the years. I have run it on my own routers for a long time
and really appreciate it. This fork does not try to improve on it; it only trims it for one
narrow use.

In that role, stock firmware still runs and listens for things an access point never uses:
ASUS device discovery, WAN detection, AiMesh sync, cloud clients, telemetry, file sharing and
more. This fork removes or switches those off, and keeps what an access point does need:

- both radios, WPA2/WPA3, VLAN-tagged guest networks (Guest Network Pro)
- the web interface (HTTPS) and SSH administration
- NTP time, WireGuard and OpenVPN (left in; see [`PLAN.md`](PLAN.md) P4.B8)

It is based on Merlin **3006.102.9** (`3006.102-wifi6` at `c73015d`).

## Support

This is an independent project, not affiliated with or endorsed by Asuswrt-Merlin or ASUS.
Support is limited: it is maintained by one person in spare time, so replies may be slow or
may not come at all.

**Please do not take anything about this fork to RMerl, the Merlin issue tracker or the Merlin
forums on SNBForums.** A problem seen on this firmware is much more likely to come from a
change made here than from upstream, and reporting it there costs volunteers time they should
spend on Merlin itself. Open an issue in this repository instead, and include the build commit
and the output of `sh /jffs/ap-harden.sh status`. If you can reproduce a problem on the
official Merlin firmware without anything from this fork, it belongs upstream as usual.

## Status

| Check | State |
|---|---|
| Firmware builds in CI | ✅ every change, GitHub Actions |
| Image compared with official 3006.102.9 | ✅ critical files present, no broken library dependencies |
| Tested on a real GT-AX6000 | ❌ not yet (recovery drill first: [`docs/RECOVERY.md`](docs/RECOVERY.md)) |
| Published release | ❌ none yet |

Day-to-day plan, task status and results log: [`PLAN.md`](PLAN.md).

## What changes compared with stock

### Removed at build time

The image is about 18 MB (26%) smaller than the official one. Removed:

- **ASUS cloud and assistants:** AiCloud tunnel, AiHome / Alexa / Google Assistant
  (`mastiff`, `aaews`, `asusnatnl`), UU game accelerator, Instant Guard
- **Discovery and monitoring:** `infosvr` (UDP 9999), `networkmap` and its helpers, avahi
  (mDNS), ASUS security daemon (`asd`), Trend Micro DPI / AiProtection (about 6.9 MB)
- **Servers an AP does not need:** IPsec (strongSwan), PPTP, SNMP, Tor, captive portal,
  UPnP IGDv2, Let's Encrypt client, Ookla speed test, AdGuard DNS, game mode
- **File and media sharing:** media server (minidlna, mt-daapd), Time Machine (netatalk),
  NFS, printer sharing

### Off switches (nvram, opt-in)

Some services cannot be compiled out without breaking Guest Network Pro, so they get a switch
instead. With a switch unset the router behaves exactly like upstream. All switches take
effect after a reboot, and the watchdog no longer restarts what they stop.

| Switch | Stops | Why |
|---|---|---|
| `disable_awsiot` | AWS IoT cloud client | Holds a persistent MQTT link to ASUS's cloud, which can change settings and restart services. Forced on by AiMesh, so it cannot be compiled out. |
| `disable_wps` | all WPS, including the hardware button | Turning WPS off in the web UI is not permanent on stock firmware: pressing the button turns it back on. |
| `disable_lltd` | `lld2d` (LLTD responder) and `lld2c` | Unauthenticated layer-2 parser on the LAN; only feeds Windows network maps and client icons. |
| `disable_netool` | backend of the web UI's Network Tools | Runs ping/traceroute/netstat as root; also hides the tab. |
| `disable_cfgsync` | AiMesh config sync (`cfg_server`, port 7788) | No mesh on a standalone AP. |
| `disable_conndiag` | AiMesh connection diagnostics | |
| `disable_amas_ctl`, `disable_obd` | AiMesh LAN control and onboarding | |
| `disable_nt_center`, `disable_wlc_nt` | notification centre and Wi-Fi client notifications | |
| `disable_infosvr`, `disable_networkmap`, `disable_mdns`, `disable_asd` | the matching daemons | Already removed from this build; the switches remain for builds that still include them. |

`tools/ap-harden.sh` also applies existing stock settings: WAN detection off
(`wanduck_down`), ASUS tunnel off, Samba, USB, telnet, SNMP and the NTP server part off, and
no firmware phone-home check. The full list with notes is at the top of
[`tools/ap-harden.sh`](tools/ap-harden.sh).

## Security notes from the source review

- **The WPS button re-enables WPS.** With WPS switched off in the GUI, a press of the hardware
  button sets it back on and restarts wireless (`rc/services.c`, `start_wps_pbc`).
  `disable_wps` closes every path: button, GUI, rc service and AiMesh onboarding.
- **AiMesh forces the AWS IoT client on** for every non-repeater model
  (`release/src-rt/Makefile`, AMAS block), even when you never use the ASUS app.
- **Network Tools argument injection (low).** `netool` builds shell commands from
  web input without quoting. httpd's input filter blocks shell metacharacters but allows
  spaces, so a logged-in user can add options to ping or traceroute.
- **Rechecking an earlier report.** Two claims in my earlier upstream proposal (RMerl PR #886)
  did not hold up against the 3006.102.9 source: infosvr has no path to set manufacturing
  mode, and HTTPS-only mode keeps port 80 on loopback only. The awsiot claim was correct.
  Details: [`docs/gt-ax6000-ap-plan.md`](docs/gt-ax6000-ap-plan.md), section 5.

## Trying it (only if you can recover a bricked router)

1. Read [`docs/RECOVERY.md`](docs/RECOVERY.md) and keep the official 3006.102.9 image and the
   ASUS Firmware Restoration tool on your PC, offline-ready.
2. Get an image: the `gt-ax6000-<commit>` artifact of a green
   [build-gt-ax6000](https://github.com/bottobot/asuswrt-merlin.ng/actions/workflows/build-gt-ax6000.yml) run (GitHub login needed,
   kept 30 days). Check it against the `sha256sums.txt` inside the artifact.
3. Flash it from the web UI (Administration › Firmware Upgrade), with the router in access
   point mode.
4. Copy `tools/ap-harden.sh` to `/jffs/`, then over SSH:

   ```sh
   sh /jffs/ap-harden.sh status          # what each switch is set to now
   sh /jffs/ap-harden.sh apply           # all switches; or name some: apply disable_wps disable_awsiot
   reboot
   sh /jffs/ap-harden.sh revert          # restores the saved previous values; reboot again
   ```

   `apply` refuses to run unless the router is in AP mode and not an AiMesh node, and saves
   the previous values to `/jffs/ap-harden.prev`.
5. Check the result with [`docs/TESTPLAN.md`](docs/TESTPLAN.md). `tools/ap-baseline.sh` and
   `tools/ap-diff.sh` capture and compare processes, listening ports and Wi-Fi state before
   and after.

## How changes are made and checked

- Each change is a small commit on top of the Merlin release; upstream history is never
  rewritten. Every new switch defaults to upstream behaviour.
- Firmware is built only in GitHub Actions
  ([`build-gt-ax6000.yml`](.github/workflows/build-gt-ax6000.yml)), in a pinned toolchain
  container.
- Every build is unpacked and compared file by file with the official 3006.102.9 image
  ([`compare-official.yml`](.github/workflows/compare-official.yml)). The check fails if a
  file an access point needs is missing or a library dependency is broken. The unmodified
  build was first shown to match the official image up to build noise
  ([`docs/baseline-3006.102.9-ci-vs-official.md`](docs/baseline-3006.102.9-ci-vs-official.md)).
- Releases will be GitHub pre-releases made from an already-verified build of the tagged
  commit, never rebuilt ([`release.yml`](.github/workflows/release.yml)).

## Repository map

| Path | Contents |
|---|---|
| [`PLAN.md`](PLAN.md) | phases, tasks, status and results log |
| [`docs/gt-ax6000-ap-plan.md`](docs/gt-ax6000-ap-plan.md) | service inventory, build-flag constraints, security background |
| [`docs/RECOVERY.md`](docs/RECOVERY.md) | restoring the official firmware |
| [`docs/TESTPLAN.md`](docs/TESTPLAN.md) | on-device acceptance tests |
| `tools/ap-harden.sh`, `ap-baseline.sh`, `ap-diff.sh` | run on the router: switches, state capture, comparison |
| `tools/pkgtb-unpack.sh`, `pkgtb-compare.sh`, `elf-needed-check.sh` | image unpacking and comparison used by CI |
| `tools/upstream-check.sh` | lists new upstream Merlin commits that touch files changed here |

## Branches

- `ap-stripdown`: the default branch, with all work here.
- `main`, `3006.*` and the other upstream branches: untouched mirrors of
  [RMerl/asuswrt-merlin.ng](https://github.com/RMerl/asuswrt-merlin.ng).

## Credits and licence

All credit for the firmware itself goes to Asuswrt-Merlin and its contributors, and to ASUS
for Asuswrt. Everything here inherits their licensing: GPL for the open components and their
own terms for the proprietary ASUS and Broadcom binaries (see `License` and
`README.proprietary`). The original project README is kept as
[`README-upstream.md`](README-upstream.md).
