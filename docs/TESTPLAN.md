# GT-AX6000 AP acceptance test plan
fmt: machine-readable. row: id|check|command_or_action|pass_criterion (exactly 4 fields; no pipes inside fields). Run after EVERY flash (PLAN.md E4). Record in PLAN-STATUS.md: date|build_sha|tag|ids_failed.
vars: AP=<ap ip> UP=<upstream switch> GV=<guest vlan id> LABEL=<build tag> PREV=<previous baseline label> B=/tmp/baseline (on router; scp to PC: scp -O -r admin@$AP:/tmp/baseline ./baseline)
order: T00 first (state capture) -> T01..T20 -> T30 last (30 min soak). Any FAIL: stop, note id, decide revert per docs/RECOVERY.md.

id|check|command_or_action|pass_criterion
T00|mode+version sane|ssh: `nvram get sw_mode; nvram get re_mode; nvram get buildno; nvram get extendno`|sw_mode=3, re_mode=0 (or empty, never 1), buildno=102.9, extendno matches build under test
T01|baseline captured|ssh: `sh /jffs/ap-baseline.sh $LABEL $B` (copy script to /jffs or /tmp first)|8 files in $B/$LABEL, no `NA:` lines other than known (list in PLAN-STATUS.md)
T02|2.4GHz associates|client on 2.4GHz SSID; router: `wl -i <2g_if> assoclist` (iface from `nvram get wl_ifnames` + `nvram get wl0_ifname`)|client MAC listed; iperf3 or ping to upstream gw 0% loss over 60 s
T03|5GHz associates|client on 5GHz SSID; `wl -i <5g_if> assoclist`|client MAC listed; ping upstream gw 0% loss over 60 s
T04|both radios up|`wl -i <if> bss` per iface in wl_ifnames|all `up`
T05|WPA3 SSID works|client joins WPA3-SAE SSID (or WPA2/3 mixed); `nvram get wl0_akm; nvram get wl1_akm` contain sae|association succeeds; ping upstream gw 0% loss; PMF per GUI setting
T06|main SSID DHCP from upstream|client on main SSID: `ipconfig /renew` or `dhclient -v`|lease from upstream DHCP server (not the AP); AP LAN IP static or reserved as intended
T07|guest SSID DHCP on guest VLAN|client on guest SSID: request DHCP|lease from upstream guest scope (subnet for VLAN $GV), gateway = upstream guest gw
T08|guest tag seen upstream|on UP: mirror/monitor AP uplink port; capture `tcpdump -nei <if> vlan $GV` (or switch MAC table shows client guest MAC on VLAN $GV tagged on AP port)|frames with 802.1Q id=$GV from guest client MAC; main-LAN client frames untagged (or native VLAN as designed)
T09|guest isolated from main LAN|guest client: ping/ssh/browse a main-LAN host and the AP LAN IP|main-LAN host unreachable; AP admin (443/22) unreachable from guest unless upstream firewall allows
T10|guest internet works|guest client: `curl -sI https://example.com` via upstream|HTTP 200/3xx
T11|https GUI reachable|PC on main LAN: `curl -skI https://$AP:8443/ -o /dev/null -w '%{http_code}\n'` (use actual https_lanport; default 8443) and login in browser|200/302; login ok; Wireless + Guest Network Pro pages render without error
T12|http not exposed|`curl -sI --max-time 5 http://$AP/` ; `nvram get http_enable` (0=http off, 2=both, 1=https only)|per intent (https-only target: connection refused or redirect to https)
T13|ssh key login|PC: `ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no admin@$AP true`; `nvram get sshd_enable; nvram get sshd_pass`|exit 0 without prompt; sshd_pass=0 if key-only intended; password auth refused
T14|no unexpected listeners|ssh: `netstat -lntu` (and `netstat -lnptu` to name owners)|only tcp 22 (dropbear), https_lanport (httpd), plus rows explicitly marked needed=y in docs/LISTENERS.md; NO udp 9999 (infosvr), 7788 (cfg_server), 18017/18018 (wanduck), 5353 (avahi), 161 (snmpd), 23 (telnetd), 445/139/21 unless intended
T15|ap-harden status matches intent|ssh: `sh /jffs/ap-harden.sh status`|diff_count=0, or each DIFF knob listed in PLAN-STATUS.md as expected (disable_* are no-ops on stock fw)
T16|ap-diff vs previous baseline|PC: `sh tools/ap-diff.sh baseline/$PREV baseline/$LABEL`|only expected changes: version strings in sys.txt, processes/listeners removed by the change under test; no change in wl.txt channels/SSIDs, vlan.txt, sdn.txt, bridge.txt unless intended
T17|vlan/SDN state intact|diff of vlan.txt, sdn.txt, bridge.txt vs PREV (inside T16 output)|identical (guest VLAN id, apgN profiles, bridge members unchanged)
T18|reboot survives|ssh: `reboot`; wait up to 180 s; repeat T00, T02, T03, T07, T11|AP back <=180 s; radios + guest + GUI work; nvram values from T00 unchanged
T19|nvram persists|after T18: `sh /jffs/ap-harden.sh status`; `nvram get sw_mode`|same as T15/T00
T20|power-cycle survives|pull DC 10 s, restore; wait 180 s; T00 + T02 + T03|same as T18
T21|LEDs sane|visual: power LED steady; radio LEDs per setting; AllLED (`nvram get AllLED`) toggle works from GUI|no stuck blink; LED state matches setting
T22|buttons sane|press WPS briefly (should do nothing destructive / WPS only if enabled); do NOT hold reset|no reboot, no factory reset; LED/GUI state unchanged
T23|time sync|`date; nvram get ntp_server0; nvram get ntpd_enable`|date within 60 s of reference; ntpd_enable=0 (client only)
T24|no cloud/telemetry procs|ssh: `ps w` (inspect for names: mastiff aaews asd conn_diag cfg_server infosvr wanduck networkmap avahi-daemon)|none of the names present, or each present proc listed as accepted in PLAN-STATUS.md for this build phase
T25|log clean at idle|ssh: `logread -l 100` (or `tail -n 100 /tmp/syslog.log`)|no repeated crash/respawn loops (same daemon restarted by watchdog every cycle)
T30|30 min soak without resets|record `date`; wait 30 min; ssh: `uptime; dmesg; wl -i <if> status` per radio|uptime >=30 min (no unplanned reboot); no new line matching wl, dhd, reset, oops or panic vs T01 dmesg (ap-baseline sys.txt lists them); radios still up; clients from T02/T03 still associated
T31|final baseline|`sh /jffs/ap-baseline.sh $LABEL-soak $B`; `sh tools/ap-diff.sh baseline/$LABEL baseline/$LABEL-soak`|only `#V` volatile lines differ (ap-diff exit 0), or every difference explained

result_fmt: `date|build_sha|tag|PASS|FAIL:<ids>|notes` -> append to PLAN-STATUS.md
gate: all T-rows PASS (or waived with reason) before next build is flashed; any FAIL in T02-T11,T13,T18,T30 = revert via docs/RECOVERY.md
unverified: https_lanport default 8443 and http_enable values, nvram key names (wl0_akm, sshd_pass, AllLED), WPS short-press behaviour on GT-AX6000 -> confirm on device in first run and fix this file
