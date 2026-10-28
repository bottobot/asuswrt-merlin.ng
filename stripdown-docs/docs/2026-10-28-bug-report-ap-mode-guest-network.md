# Bug report: GT-AX6000 in AP mode: Guest Network Pro, VLAN 52 template, and related findings

> Public copy: MAC addresses, SSIDs, people's names, SSH details and security findings are
> redacted or held back. The owner keeps the full version.

Written 2026-10-28 by netsec session 3b694e (AgentBoard task 3b694e). Sources: the router syslog export
`~/Downloads/reports/syslog.txt` (2026-10-20 04:50 to 2026-10-26 01:50 PDT, 18,545 lines), two live
read-only SSH inspections, one live change with automatic rollback, the firewall's DHCP logs in Loki, and the
router's syslog in Loki. Each finding says whether this session saw it directly or another session reported it.

Times are PDT unless marked Z (UTC). No secrets appear here: no passwords, PSKs or nvram dumps.

## Setup

| Item | Value |
|---|---|
| Router | ASUS GT-AX6000, AP mode (`sw_mode=3`), LAN IP `192.168.2.174`, behind OPNsense |
| Firmware during this session's findings | Merlin `3.0.0.6.102.8_0` (read live 2026-10-26 10:22Z; uptime about 36.7 days) |
| Firmware since 2026-10-26 12:15Z | Merlin `3006.102.9`, flashed by the owner |
| Guest network | Guest Network Pro profile `apg1`, SSID `GUEST-SSID` on `wl0.1` (2.4 GHz) and `wl1.1` (5 GHz), VLAN 30, bridge `br30`, uplink `eth0.30`. DHCP comes from OPNsense on `ix1_vlan30` (`192.168.30.0/24`), not from the router |
| Main networks | `wl0`/eth6 SSID `MAIN-24-SSID` (2.4 GHz) and `wl1`/eth7 `MAIN-5G-SSID` (5 GHz), both on `br0` = VLAN 2 |

---

## Bug 1 (main): Guest Network Pro keeps a stale VLAN 52 subnet and keeps starting a dnsmasq that can never bind

**Seen directly by this session (firmware 102.8). The recurrence on 102.9 was reported by session 088616.**

### Symptom

After each Guest Network Pro apply, the router regenerates `/etc/dnsmasq-1.conf` for a bridge `br52` with
address `192.168.52.1`. In AP mode `br52` does not exist, so dnsmasq fails every time:

```
Oct 25 03:45:47 wlceventd: main(1239): wlceventd Start...
Oct 25 03:45:47 dnsmasq[10958]: failed to create listening socket for 192.168.52.1: Cannot assign requested address
Oct 25 03:45:47 dnsmasq[10958]: FAILED to start up
Oct 25 05:40:08 dnsmasq[3292]: failed to create listening socket for 192.168.52.1: Cannot assign requested address
Oct 25 05:40:08 dnsmasq[3292]: FAILED to start up
Oct 25 06:03:34 dnsmasq[10996]: failed to create listening socket for 192.168.52.1: Cannot assign requested address
Oct 25 06:03:34 dnsmasq[10996]: FAILED to start up
```

Each failure comes about 14 seconds after a wireless rebuild. The rebuild shows as kernel `Register interface [wl0.1]`
and `[wl1.1]` lines, then `wlceventd Start...`. On 2026-10-25 the owner edited the guest profile in the web UI
four times (wireless rebuilds at 03:05, 03:45, 05:39 and 06:03; no SSH session existed at those times). Three of
the four rebuilds produced the failure. A 2.4 GHz 40 MHz chanspec `0x1909` also appeared during those rebuilds,
although `wl-chan` kept reporting eth6 as `11(0x100b)`.

### Live state (read 2026-10-26 10:22Z, firmware 102.8)

```
sdn_rl=<0>DEFAULT>1>0>0>0>0>0>0>0>0>0>0>0>0>0>0>0>0>WEB>0>0>0<1>Customized>1>1>1>1>0>0>0>0>0>0>0>0>0>0>0>0>0>WEB>0>0>0
vlan_rl=<1>30>0>
subnet_rl=<1>br52>192.168.52.1>255.255.255.0>1>192.168.52.1>192.168.52.254>86400>>,>>0>>0>0>1>1000>2000>,,>0>1>
subnet_rl_x=(identical to subnet_rl)
apg_ifnames=br30
apg1 enable=1 ssid=GUEST-SSID dut_list=<AP-MAC>3> ap_isolate=1
```

`/etc/dnsmasq-1.conf` (written 2026-10-25 06:03):

```
bind-interfaces
listen-address=192.168.52.1
dhcp-range=br52,192.168.52.1,192.168.52.254,255.255.255.0,86400s
interface=br52
except-interface=lo
```

Live interfaces: only `br0 192.168.2.174/24` has an IPv4 address. `br30` exists with no address, and its
members are `eth0.30` through `eth7.30`, `wl0.1` and `wl1.1`. No dnsmasq process was running.

So the profile carries both a VLAN reference (`vlan_rl` index 1 = VID 30, which builds `br30` correctly) and a
subnet reference (`subnet_rl` index 1 = `br52`/`192.168.52.1`, router-run DHCP enabled). In AP mode the
firmware honours the VLAN for bridging but still writes and launches a dnsmasq instance for the subnet.

Field order of `sdn_rl` is inferred, not taken from source: `<idx>name>enable>vlan_idx>subnet_idx>apg_idx>…`.
Profile 1 = enable 1, vlan_idx 1, subnet_idx 1, apg_idx 1. The cleanup below behaved as that reading predicts.

### Where the stale entry comes from

When a Guest Network Pro profile is created in the web UI, ASUS fills in its own default subnet
(`192.168.52.0/24` on VLAN 52, router-run DHCP). The creation dialog has no VLAN field (reported by 088616), so
the profile always starts on VLAN 52. Changing the VLAN ID to 30 afterwards leaves the 192.168.52.1 subnet entry
in place. The first build of this guest network on 2026-07-15 hit the same template (netsec memory
`project_quarantine_vlan30.md`).

### Impact

- **Today:** log noise only. Nothing ever serves `192.168.52.x`, and guest clients get DHCP from OPNsense on VLAN 30.
- **Risk:** the profile still holds a complete router-run DHCP definition. If a future firmware or UI path
  creates `br52`, or attaches the subnet to the real guest bridge, the router would hand guests `192.168.52.x`
  addresses behind its own NAT. Guests would then bypass VLAN 30 and the OPNsense rules.
- **Recreate trap (088616, 2026-10-26 06:21 on 102.9):** deleting and recreating the profile put it on
  VLAN 52 (`br52`), so every guest device lost its network. A second apply during the WiFi restart hung the router
  until a power cycle. What worked: create the profile, then **edit** it, set the VID to 30, apply **once**, and wait
  about 2 minutes. The profile was back on VLAN 30 at 09:28 that day, but the stale `br52` subnet entry returned.

### Workaround that worked (this session, 2026-10-26 10:25Z, firmware 102.8)

Script `netsec/scripts/asus/sdn52-cleanup-20261026.sh` (in worktree `.agentboard/wt/3b694e`). It ran detached,
because the admin laptop reached the router over WiFi, and reported back through syslog tag `sdn52-cleanup`.

1. Preconditions: the exact `sdn_rl`, `subnet_rl` and `subnet_rl_x` values above; `vlan_rl=<1>30>0>`;
   `apg_ifnames=br30`; `wl0.1`, `wl1.1` and `eth0.30` present in `br30`.
2. Back up the three values to `/jffs/netsec-sdn52-cleanup-20261026T102530Z/`.
3. Change profile 1's `subnet_idx` in `sdn_rl` from 1 to 0, and set `subnet_rl` and `subnet_rl_x` to empty. Commit,
   delete `/etc/dnsmasq-1.conf`, run `service restart_wireless`, wait 35 s, then re-run `/jffs/scripts/vlan30-uplink.sh`.
4. Verify, or else restore the backup and restart: no `192.168.52` anywhere in nvram, in interface addresses or in
   any `/etc/dnsmasq*.conf`; no new `192.168.52` line in `/tmp/syslog.log` after a marker; `br30` still holds
   `wl0.1`, `wl1.1` and `eth0.30`; neither guest interface in `br0`; br30 `isolated` = 0 on `eth0.30` and 1 on
   `wl0.1`/`wl1.1`; `wl -i wl0.1|wl1.1 ap_isolate` = 1; all four live SSIDs unchanged; and a snapshot of
   SSID/auth/MFP/bss_enabled/ap_isolate for wl0, wl0.1, wl1, wl1.1 plus the apg1 fields identical before and after.

Result: `VERIFIED` at 10:26:05Z. A guest phone joined `wl1.1` at 10:28:14Z and received OPNsense `DHCPACK(ix1_vlan30)
192.168.30.135`, so VLAN 30 worked end to end. Before the next delete-and-recreate there were no more dnsmasq
failures. This contradicts, in a narrow way, the standing note that Guest Network Pro "cannot be built via raw
nvram": removing a dangling subnet reference by nvram survived `restart_wireless`. Creating profiles still
belongs in the UI.

**Caveat:** the owner's UI recreate later put the stale entry back. Read live on 2026-10-28, `sdn_rl`,
`subnet_rl` and `subnet_rl_x` are again **byte-for-byte the strings above**, so the script's preconditions
match and it could run again unchanged. It would last only until the next delete-and-recreate.

### Suggested fix in the fork (unverified against source)

- In AP mode, skip generating and launching dnsmasq instances for Guest Network Pro subnets entirely. In AP
  mode the router never routes, so a guest subnet's DHCP can only be served upstream.
- Or: when a profile has a VLAN set and the router is not in router mode, ignore its `subnet_idx`.
- UI: give the creation dialog a VID field, or don't pre-fill the VLAN 52 template in AP mode.
- Next step: find the code that turns `sdn_rl`/`subnet_rl` into `/etc/dnsmasq-<n>.conf` and starts the instance. Search
  `release/src/router/rc/` for `subnet_rl` and `dnsmasq-%d.conf`. The file location has not been checked.

---

## Finding 2: in AP mode the guest VLAN is bridged onto every LAN port

**Seen directly by this session (102.8).** `br30` members were `eth0.30, eth1.30, eth2.30, eth3.30, eth4.30,
eth5.30, eth6.30, eth7.30, wl0.1, wl1.1`, and `/proc/net/vlan/config` listed VLAN 30 sub-interfaces on eth0 to eth7.
Only `eth0` (the 2.5G uplink to the switch) needs VLAN 30.

**Live readout 2026-10-28 06:2xZ (firmware 102.9, uptime 40.2 h)**: every port flag, counter and learned MAC.

| br30 port | isolated | STP state | link | rx frames | tx frames |
|---|---|---|---|---|---|
| `eth0.30` (uplink, 2.5G) | **0** | forwarding | up | 10,723,284 | 874,557 |
| `eth1.30` (LAN 1, household PC's port) | 1 | forwarding | up 1G | **0** | 769 |
| `eth2.30`–`eth5.30` | 1 | disabled | no carrier | 0 | 0 |
| `eth6.30` / `eth7.30` (main 2.4/5 GHz radios) | 1 | forwarding | up | 0 | 769 each |
| `wl0.1` (guest 2.4) | 1 | forwarding | up | 17,204 | 12,481 |
| `wl1.1` (guest 5) | 1 | forwarding | up | 857,643 | 10,711,460 |

All ports: hairpin 0, learning 1, unicast/multicast/broadcast flood 1, proxy-ARP 0, neighbour suppression 0.
Bridge: STP off, no VLAN filtering, `group_fwd_mask 0x0`. ebtables filter, nat and broute are empty, so
isolation rests only on the bridge `isolated` flags plus `wl`/`dhd` `ap_isolate`.

What this shows:
- **No wired device has ever joined the guest VLAN since boot.** `eth1.30` received 0 frames, and the br30 MAC
  table has nothing learned on `eth1.30`–`eth5.30`. Learned MACs: firewall `FIREWALL-MAC` and SODOLA switch
  `SWITCH-MAC` on `eth0.30`; the S24 `PHONE-MAC` and pikiosk `KIOSK-MAC` on `wl1.1`.
- **The isolation is not the firmware's doing.** `/jffs/scripts/vlan30-uplink.sh` (from session 088616, run from
  `services-start` and `service-event-end`) sets it. After the profile recreate on 2026-10-26 it logged
  `09:26:36 vlan30-scope: guest isolation re-asserted: wl0.1_ap_isolate wl1.1_ap_isolate apg1_ap_isolate dhd:wl0.1
  dhd:wl1.1 eth1.30=1 eth2.30=1 … eth7.30=1 wl0.1=1 wl1.1=1`. So a freshly built Guest Network Pro profile comes up
  with **every** br30 port non-isolated and with `ap_isolate` off, even though the UI profile is the isolated guest
  kind. Between a profile apply and the script's next run, guests can reach each other and any VLAN-30-tagged
  wired host.
- **Small outward leak:** `eth1.30`, `eth6.30` and `eth7.30` each sent exactly 769 frames (75,849 bytes, about 99 bytes
  each) in 40 h. Isolated ports can only receive from the non-isolated uplink, so these are broadcasts or
  multicasts flooded from the firewall side of VLAN 30 (e.g. ARP), sent 802.1Q-tagged onto the household PC's cable and onto
  both main SSIDs. Clients drop tagged frames, but a host capturing on that cable or on the main WiFi can read
  them. Low sensitivity; it shows that guest-VLAN broadcasts reach the main network as tagged frames.
- `eth6.30`/`eth7.30` (VLAN 30 on the main radios' own interfaces) serve no purpose in AP mode.

Relevant settings: `lan1_ifname=br30`, `lan1_ifnames=wl0.1 wl1.1 eth0.30 … eth7.30`, `apg_ifnames=br30`,
`apg_br_info=<30>br30>` (new in 102.9), `apg1_dut_list=<AP-MAC>3>`, `lanports=1 2 3 4 5`,
`wanports=0`, `wans_lanport=1`, `br0_ifnames=eth0 … eth5`.

**Fork angle:** in AP mode, (1) create Guest Network Pro VLAN sub-interfaces only on the uplink port, never on
LAN ports or the main radios; (2) when the profile asks for guest isolation, apply it at build time on all three
layers (bridge `isolated` on every non-uplink port, `wl ap_isolate`, `dhd ap_isolate`), so no window opens after
each apply. This may sit in the `dut_list`/port-binding code of the SDN service; the location hasn't been checked.

---

## Finding 3: the 102.9 upgrade moved the guest interfaces into br0 (reported by 088616, not seen by this session)

The owner flashed `3006.102.9` at 2026-10-26 12:15Z. The nvram migration put `wl0.1 wl1.1` into
`lan_ifnames`/`br0` and set every `br0` port to `isolated`, the uplink included. That cut all WiFi off from the
firewall for 48 minutes. `/jffs/scripts/vlan30-uplink.sh` now repairs this on every boot and service event.
Details are in netsec memory `project_router_hardening.md` and `project_quarantine_vlan30.md`.

---

## Finding 4: guest isolation needs three layers and can drift (reported by 088616)

Reliable client isolation on the guest SSID needs **all** of: `wl -i wl0.1|wl1.1 ap_isolate 1` (plus the
matching nvram), `dhd -i wl0.1|wl1.1 ap_isolate 1` (the radios are PCIe offload dongles, and the host dhd relays
same-radio traffic), and br30 port `isolated` = 1 on the WiFi ports and 0 on the uplink. The web UI exposes none
of the three. Open lead from 2026-10-27: acsd flips eth6 between 20 and 40 MHz about every 15 minutes (OBSS
coexistence downgrade, neighbour on channel 6), and each flip probably resets `dhd -i wl0.1 ap_isolate` to 0. The
15-minute `guest-iso-watch` job collects proof. The candidate fix is a fixed 20 MHz on 2.4 GHz.

**Seen by this session on 2026-10-28:** the drift is real. The uplink script re-set `dhd:wl0.1` on its own at
2026-10-26 11:53:27 and 2026-10-27 07:15:05; both times only the 2.4 GHz guest's dhd layer had reverted. Settings
are `wl0_chanspec=11u` (40 MHz upper), `wl0_bw=0` (auto 20/40) and `wl0_obss_coex=1`, but the live chanspec is
`11 (0x100b)` (20 MHz), so OBSS coexistence has downgraded the channel. That fits the theory. At read time all
guest layers were correct: `wl0.1` and `wl1.1` at wl=1, dhd=1.

---

## Finding 5: per-interface MAC deny does not follow a renamed SSID (seen by this session; a limitation, not a defect)

`wl0_macmode=deny` with `wl0_maclist=NEIGHBOUR-TUYA-MAC` (a neighbour's Tuya device that auth-loops) applies to
`wl0` only. After the 2026-10-21 name swap the guest slot `wl0.1` carries SSID `GUEST-SSID`, so the Tuya started
probing `wl0.1` instead:

```
Oct 25 10:45:53 hostapd: wl0.1: STA NEIGHBOUR-TUYA-MAC IEEE 802.11: disassociated
Oct 25 11:58:41 hostapd: wl0.1: STA NEIGHBOUR-TUYA-MAC IEEE 802.11: disassociated
```

It never completed a handshake, almost certainly because `wl0.1` is WPA3-only. The deny entry should also be set
on `wl0.1`, or on the profile if Guest Network Pro supports it.

---

## Finding 6: driver error noise on every wireless rebuild (seen by this session; looks benign)

Each rebuild (2026-10-21 10:31 and the four on 2026-10-25) logs the same burst. Counts across the export:

| Message (exact text) | Count |
|---|---|
| `CFG80211-ERROR) wl_dfs_cac_notify_status :` | 80 |
| `No wdev corresponding to bssidx: 0x1 found! Ignoring event.` | 24 |
| `CFG80211-ERROR) wl_event_handler :` | 24 |
| `buf_key_b4_m4 failed; error -23` | 20 |
| `CFG80211-ERROR) wl_cfg80211_add_virtual_iface :`, `wl_alloc_netinfo :`, `wl_dealloc_netinfo_by_wdev :`, `wl_cfg80211_iface_state_ops :` | 20 each |
| `IGMP Query send failed` | 10 |
| `Wowl not supported (-23)`, `Get event_msgs error (-19)`, `Dongle is already up`, `p2p inactive` (with `CFGP2P-ERROR) wl_cfgp2p_find_ndev :`) | 10 each |

None of these caused a fault: the interfaces came back, clients reassociated, and the bridges re-formed. Every
rebuild also restarts the 60-second DFS channel availability check on 5 GHz channel 100 (`DFS state 1`, then
`state 2` 60 s later), so each guest-profile apply costs about a minute of 5 GHz outage. Useful for the
strip-down as a known-noise baseline when judging whether a change made things worse.

---

## Finding 7: the 2.5G uplink dropped for 59 s (seen by this session; cause unknown)

```
Oct 24 08:27:10 kernel: eth0 (Int switch port: 5) (Logical Port: 5) (phyId: 11) Link DOWN.
Oct 24 08:27:10 kernel: [NTC xport] xport_reset: rc = 0; intf = 1 port = 0 spd = 2.5G dup = 1
Oct 24 08:28:08 kernel: MACSEC: macsec is not enabled
Oct 24 08:28:09 kernel: [NTC xport] xport_init: rc = 0; intf = 1 port = 0 spd = 2.5G dup = 1
Oct 24 08:28:09 kernel: eth0 (Int switch port: 5) (Logical Port: 5) (phyId: 11) Link Up at 2500 mbps full duplex
```

During that minute the AP's whole uplink (to SODOLA switch port P2) was down. Nothing in the router log explains
it; check the switch side first. Separately, `eth1` (a LAN port, probably the household PC) dropped for 20 s at
`Oct 22 02:08:11`.

---

## Finding 8: owner-side tooling gaps found in the same export (not firmware bugs)

- **Stats logger blind to guest slots.** The owner's 5-minute `wl-rssi`, `wl-tput`, `wl-chan` and `wifi-sta-ip`
  lines poll only `eth6` and `eth7`. After the 2026-10-21 swap most clients sit on `wl0.1`/`wl1.1`, so about six
  devices vanished from the telemetry. Add the virtual interfaces.
- **nvram-diff baseline is stale.** The 02:00 daily `nvram-diff` compares against a January/July snapshot and
  repeats about 115 unchanged lines every day, which buries real changes. The real changes in the window were the
  2026-10-21 name swap (`wl0_ssid` `GUEST-SSID`→`MAIN-24-SSID`; `wl0.1_ssid`, `wl1.1_ssid`, `apg1_ssid` `MAIN-24-SSID`→`GUEST-SSID`) and
  `wl0_dpp_status`/`wl1_dpp_status` flips. Re-baseline it.
- **Firmware-update flag.** `webs_state_flag=1`, `webs_state_info=3006_102_9_0` announced 102.9 before the owner
  flashed it.

---

## Finding 9: main-network isolation policy and Full Dongle readout (corrected 2026-10-28)

| Main radio | SSID | live `wl ap_isolate` | live `dhd ap_isolate` | nvram |
|---|---|---|---|---|
| eth6 (2.4 GHz) | MAIN-24-SSID | 1 | 1 | `wl0_ap_isolate=1` (takeover read at 10:53Z) |
| eth7 (5 GHz) | MAIN-5G-SSID | 1 | **0** | `wl1_ap_isolate=0` |

- **Correction:** `wl=1, dhd=0` does not by itself show stale or contradictory isolation settings. In the
  published impl87 Full Dongle driver, firmware sends intra-BSS traffic to the host, and DHD forwards it
  between associated stations when its per-interface `ap_isolate` is zero. See
  [dhd_linux.c, initialization at lines 12298-12306 and forwarding from line 6796](https://github.com/RMerl/asuswrt-merlin.ng/blob/2cd9ba28fd956d0aac8347bbb620df82914b6e01/release/src-rt-5.04axhnd.675x/bcmdrivers/broadcom/net/wl/impl87/sys/src/dhd/sys/dhd_linux.c#L12298).
  This source explains why a non-isolated main network can retain `wl=1`; it is not an end-to-end device test.
- The original prediction that the next restart would flip 5 GHz behavior was unsupported and is withdrawn.
  Two password-rotation attempts at 07:42Z and 07:46Z restarted wireless and rolled back; the latter failed
  solely because its verifier wrongly required `wl=0`. At 10:53Z main 5 GHz still read saved=0, wl=1, dhd=0,
  with `br0/eth7/isolated=0`. A direct and explicit BSS-zero `wl ... ap_isolate 0` each returned success but
  still read back 1, without changing either guest's isolation controls.
- The owner subsequently chose isolation off and a password change for `MAIN-5G-SSID`. That authorization does
  not choose a new policy for 2.4 GHz `MAIN-24-SSID`, which remains saved=1, wl=1, dhd=1.
- Revised validation checks saved=0, DHD=0, and main bridge isolation=0, while retaining the Full Dongle
  firmware forwarding mode and all guest controls. Physical same-radio peer connectivity still needs a
  test with two owner-controlled clients.

---

## Finding 10: firmware rollback is not a fix (decision note, 2026-10-28)

The owner asked whether to return to 102.8. Every guest-network problem here except Finding 3 was already
present on 102.8: this session's Bug 1 evidence and workaround were on 102.8, and the VLAN 52 template dates from
the July build. Finding 3 is repaired, and the uplink script re-applies the repair on every boot and service
event. A downgrade would run another nvram migration, the event that caused Finding 3, and would drop 102.9's
fixes. Recommendation: stay on 102.9.

---

## What changed on the router because of this session

| When | Change | State now |
|---|---|---|
| 2026-10-26 10:25Z | Stale VLAN 52 subnet removed (Bug 1 workaround), verified, backup on `/jffs` | Undone by the owner's UI recreate at 13:21Z; the stale `br52` entry is back but dormant |
| 2026-10-28 11:00Z | Owner-requested `MAIN-5G-SSID` password rotation, saved isolation off and DHD isolation off | `VERIFIED_CONFIG`; lilguy subsequently reconnected using the vault-matching password |
| 2026-10-28 11:10Z | Owner requested avoiding all DFS channels: fixed 36/80, 80 MHz bandwidth, automatic DFS channel selection off | `VERIFIED`; live 36/80; DFS IDLE at 0 ms; credential unchanged and guest isolation intact |

Later continuation: two `MAIN-5G-SSID` credential/isolation changes at 2026-10-28 07:42Z and 07:46Z rolled back,
confirmed by their router receipts at 10:53Z. A subsequent bounded isolation diagnostic attempted to set only
the main 5 GHz firmware control off, observed it still reading 1, and reasserted the guest helper. No guest
control changed during that diagnostic. A continuation attempt at 10:59Z also rolled back when the readiness
check accepted the guest bridge before the main radio's bridge port had returned. The shared readiness
check was corrected and locally tested. The final rotation receipt
`/jffs/netsec-main-5g-resume-20261028T110042Z/state` contains `VERIFIED_CONFIG`: credential readback matched,
main saved/DHD/bridge isolation all zero, guest controls intact, other snapshotted settings unchanged.
An independent read at 11:03:18Z reconfirmed the receipt and guest controls. Channel 100/80 needed a DFS CAC
after restart; once broadcasting, lilguy reconnected to `AP-5G-BSSID` on 5500 MHz as `.2.117` and
reached a wired household PC `.2.140` over WiFi (3/3 ICMP replies). Same-radio peer testing remains separate.

## Current state (2026-10-28 06:00Z, from the firewall's DHCP logs in Loki)

The guest profile is on VLAN 30 and working. In the previous 24 h OPNsense acknowledged DHCP on `ix1_vlan30`
for WorkLaptop `192.168.30.194`, pikiosk `192.168.30.146` (static reservation), Blink `192.168.30.166` and
a household S24 `192.168.30.135`.

## Open items

1. Bug 1 recurs on every profile recreate. Decide between periodic cleanup of the dormant entry (re-read the values
   first) and a firmware fix in this fork.
2. Finding 2: checked 2026-10-28. The LAN-port VLAN 30 interfaces are isolated (by the uplink script, not the
   firmware) and have never carried wired traffic. Still open: the post-apply window, and the 769 tagged
   broadcasts leaking onto the household PC's cable and the main SSIDs.
2a. Finding 9: owner-selected isolation off and password rotation on `MAIN-5G-SSID` are complete; router
    configuration readback and lilguy reconnection passed. Same-radio peer testing remains open.
3. Finding 4: confirm the acsd/dhd drift theory from the `guest-iso-watch` logs (Loki `|~ "guest-iso-watch|COEX: downgraded"`).
4. Finding 5: copy the Tuya deny entry to `wl0.1`.
5. Finding 8: extend the stats logger and re-baseline nvram-diff.

## Provenance

Later owner channel policy: keep 5 GHz on non-DFS channels. Receipt
`/jffs/netsec-non-dfs-5g-20261028T111023Z/` verifies fixed `wl1_chanspec=36/80`, `wl1_bw=3`, `acs_dfs=0`,
and generated exclusion of channel 100/80. Live DFS status is IDLE, 0 ms. An earlier channel attempt
`20261028T110716Z` rolled back because its verifier wrongly demanded `wl1_acs_dfs=0`; startup regenerates
that regulatory flag from `wl1_reg_mode`, so the corrected script leaves it alone and validates the UI's
global preference plus its generated channel exclusion instead. The takeover handoff in netsec worktree
`e633f6` records the complete result.

- Syslog export: `~/Downloads/reports/syslog.txt` (owner's download, 2026-10-26 01:53).
- Live read-only inspection script and output: netsec session scratchpad `asus-sdn52-inspect.sh` (contents
  reproduced above).
- Full flag readout of 2026-10-28 (secrets redacted): `/var/tmp/asus-bridge-flags-20261028.out` on lilguy.
- Workaround script: `netsec/.agentboard/wt/3b694e/scripts/asus/sdn52-cleanup-20261026.sh`; router backup
  `/jffs/netsec-sdn52-cleanup-20261026T102530Z/`.
- Other sessions' findings: netsec memory `project_quarantine_vlan30.md` and `project_router_hardening.md`; handoff
  `netsec/docs/handoff-20261026-vlan30-scope.md` (session 088616).
