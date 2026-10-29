#!/bin/sh
# ap-baseline.sh <label> [outdir=/tmp/baseline]
# RUNS ON ROUTER (busybox ash). Writes <outdir>/<label>/{ps,listen,nvram,wl,bridge,vlan,sdn,sys}.txt
# Stable-diff rules: PID/VSZ/STAT dropped from ps; listeners sorted w/o PID; MACs masked (wl,bridge,sdn);
#   secrets (key|psk|passwd|password|secret|crt|token; sdn also 'security') -> REDACTED;
#   lines prefixed '#V ' are volatile (uptime, free, loadavg) and ignored by ap-diff.sh.
# Missing command -> line 'NA:<cmd>'. NOTE /tmp is RAM: scp the dir off the router before reboot.
# Pair: tools/ap-diff.sh. Scope: PLAN.md P2.3.
set -u
umask 077

label=${1:-}
out=${2:-/tmp/baseline}
case $label in
  ''|*/*|.*) echo "usage: ap-baseline.sh <label> [outdir=/tmp/baseline]" >&2; exit 2 ;;
esac
D=$out/$label
T=$D/.tmp
mkdir -p "$D" "$T" || exit 1
trap 'rm -rf "$T"' EXIT INT TERM

have() { command -v "$1" >/dev/null 2>&1; }
run() { if have "$1"; then "$@" 2>&1; else echo "NA:$1"; fi; }
nvget() { if have nvram; then nvram get "$1" 2>/dev/null; else echo "NA:nvram"; fi; }
mask_mac() { sed -E 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/XX:XX:XX:XX:XX:XX/g'; }
vol() { sed 's/^/#V /'; }
# redact [extra_alt]: blank value of any key=value line whose KEY matches the secret pattern
redact() {
  awk -v p="key|psk|passwd|password|secret|crt|token${1:+|$1}" '
    { i = index($0, "="); if (i == 0) { print; next }
      k = tolower(substr($0, 1, i - 1))
      if (k ~ p) print substr($0, 1, i) "REDACTED"; else print }'
}

# ps.txt: USER COMMAND..., sorted, own helper processes dropped
run ps w > "$T/ps.raw"
awk '
  $1 == "PID" { next }
  $1 ~ /^[0-9]+$/ { printf "%s", $2; for (i = 5; i <= NF; i++) printf " %s", $i; printf "\n"; next }
  { print }' "$T/ps.raw" | grep -v -e 'ap-baseline' -e '^[^ ]* ps w$' | sort > "$D/ps.txt"

# listen.txt: proto local_addr:port program (no PIDs), unique+sorted
run netstat -lnptu | awk '
  $1 ~ /^(tcp|udp)/ { p = $NF; sub(/^[0-9]+\//, "", p); if (p == "-" || p ~ /^[0-9]+$/) p = "?"; print $1, $4, p; next }
  /^NA:/ { print }' | sort -u > "$D/listen.txt"

# nvram.txt: selected keys + every ^disable_ key, secrets redacted
{
  if have nvram; then
    for k in sw_mode re_mode wlc_psta x_Setting cfg_master wanduck_down networkmap_enable \
             aae_disable_force sshd_enable telnetd_enable enable_samba usb_enable ntpd_enable \
             snmpd_enable firmware_check_enable; do
      printf '%s=%s\n' "$k" "$(nvram get "$k" 2>/dev/null)"
    done
    nvram show 2>/dev/null | grep '^disable_' | sort
  else
    echo "NA:nvram"
  fi
} | redact > "$D/nvram.txt"

# wl.txt: per iface in wl_ifnames (+ virtual wlX.Y from sysfs): status minus rssi/snr/noise, ssid, bss
wl_one() {
  echo "## $1"
  run wl -i "$1" status | sed -E 's/(RSSI|rssi|SNR|snr|noise|Noise):[[:space:]]*-?[0-9]+[[:space:]]*(dBm|dB)//g' \
    | grep -viE 'rssi|noise|snr'
  echo "# ssid"; run wl -i "$1" ssid
  echo "# bss"; run wl -i "$1" bss
}
{
  seen=" "
  for i in $(nvget wl_ifnames); do
    seen="$seen$i "
    wl_one "$i"
  done
  for n in /sys/class/net/wl*; do
    [ -e "$n" ] || continue
    i=${n##*/}
    case $i in *.*) ;; *) continue ;; esac
    case $seen in *" $i "*) continue ;; esac
    seen="$seen$i "
    wl_one "$i"
  done
} 2>&1 | mask_mac > "$D/wl.txt"

# bridge.txt
run brctl show | sed -E 's/[0-9a-f]{4}\.[0-9a-f]{12}/XXXX.XXXXXXXXXXXX/' > "$D/bridge.txt"

# vlan.txt
{
  echo "# /proc/net/vlan/config"
  if [ -r /proc/net/vlan/config ]; then cat /proc/net/vlan/config; else echo "NA:/proc/net/vlan/config"; fi
  echo "# ip -d link (vlan lines)"
  run ip -d link show | awk '/^[0-9]+: /{n=$2} /vlan (protocol|id)/{print n, $0} /^NA:/{print}'
} > "$D/vlan.txt" 2>&1

# sdn.txt: Guest Network Pro / SDN / VLAN nvram
{
  if have nvram; then
    nvram show 2>/dev/null | grep -E '^(sdn_rl|apg[0-9]+_|vlan_rl|mtlan)' | sort
  else
    echo "NA:nvram"
  fi
} | mask_mac | redact security > "$D/sdn.txt"

# sys.txt
{
  for k in firmver buildno extendno; do printf '%s=%s\n' "$k" "$(nvget "$k")"; done
  run uptime | vol
  run free | vol
  if [ -r /proc/loadavg ]; then vol < /proc/loadavg; else echo "#V NA:/proc/loadavg"; fi
  echo "# dmesg (last 300, filtered, timestamps stripped)"
  run dmesg | tail -n 300 | grep -iE 'wl|dhd|reset|oops|panic|^NA:' | sed -E 's/^\[[ 0-9.]*\] *//'
} > "$D/sys.txt" 2>&1

echo "baseline=$D"
for f in "$D"/*.txt; do echo "$(wc -c < "$f") ${f##*/}"; done
echo "reminder: /tmp is RAM; copy $D off the router (scp) before reboot"
