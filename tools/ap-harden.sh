#!/bin/sh
# ap-harden.sh apply|revert|status [knob...]
# RUNS ON ROUTER (busybox ash). Pure-AP nvram hardening; PLAN.md P1/P3.
# KNOBS line fmt: name=value_on|value_off|comment
#   value_on  = hardened target (apply sets it); value_off = stock default (doc only; revert uses the saved file)
#   <unset>   = 'nvram unset name'
#   disable_* = honoured only by rc guards (RMerl PR #886 pattern, PLAN P3); no-op on stock firmware
# apply : needs sw_mode=3 and re_mode!=1; saves previous values to /jffs/ap-harden.prev (never overwrites an
#         existing entry; appends entries for knobs not yet saved); nvram commit; reboot to take effect
# revert: restores values from the prev file, drops restored entries, removes file when empty
# status: table knob|current|target|match
PREV=${AP_HARDEN_PREV:-/jffs/ap-harden.prev}

KNOBS='
wanduck_down=1|0|stop wanduck (no WAN in AP)
aae_disable_force=1|0|disable ASUS AAE tunnel (mastiff/aaews)
enable_samba=0|1|samba off
usb_enable=0|1|usb stack off
ntpd_enable=0|0|NTP server part off; ntp client unaffected
telnetd_enable=0|0|telnet off
snmpd_enable=0|0|snmp off
firmware_check_enable=0|1|no phone-home fw check
disable_infosvr=1|<unset>|infosvr udp9999
disable_networkmap=1|<unset>|networkmap
disable_mdns=1|<unset>|avahi mdns
stop_amas_lldpd=1|<unset>|lldpd: existing knob, checked in start_amas_lldpd before notify hand-off; blocks start, does not kill a running lldpd (reboot)
disable_cfgsync=1|<unset>|cfg_server+cfg_client tcp/udp7788; no AiMesh after; verify GNP profile applies
disable_conndiag=1|<unset>|conn_diag+amas_ssd_cd
disable_amas_lib=1|<unset>|amas_lib: native ASUS knob in prebuilt amas_lib.o (start_amas_lib+amaslib_check)
disable_obd=1|<unset>|obd+obd_eth onboarding (init check_services also skipped)
disable_amas_ctl=1|<unset>|amas_lanctrl (AiMesh VIF onboarding/LAN control); non-RE only; test GNP after
disable_asd=1|<unset>|asd
disable_nt_center=1|<unset>|nt_center
disable_wlc_nt=1|<unset>|wlc_nt
'

UNSET='<unset>'
cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in apply|revert|status) ;; *) echo "usage: ap-harden.sh apply|revert|status [knob...]" >&2; exit 2 ;; esac
if ! command -v nvram >/dev/null 2>&1; then echo "NA:nvram (run on router)" >&2; exit 1; fi

T=/tmp/ap-harden.$$
mkdir -p "$T" || exit 1
trap 'rm -rf "$T"' EXIT INT TERM

printf '%s\n' "$KNOBS" | sed '/^[[:space:]]*$/d;/^#/d' > "$T/all"

# selection -> $T/sel (full knob lines)
: > "$T/sel"
if [ $# -eq 0 ]; then
  cp "$T/all" "$T/sel"
else
  for k in "$@"; do
    if grep "^$k=" "$T/all" >> "$T/sel"; then :; else echo "unknown knob: $k" >&2; exit 2; fi
  done
fi

# snap: nvram show -> $T/snap (re-run after changes)
snap() { nvram show 2>/dev/null > "$T/snap"; }
# state NAME -> S_SET (1/0), S_VAL
state() {
  _l=$(grep "^$1=" "$T/snap" | head -n 1)
  if [ -n "$_l" ]; then S_SET=1; S_VAL=${_l#*=}; else S_SET=0; S_VAL=; fi
}
show() { if [ "$S_SET" -eq 1 ]; then printf '%s' "$S_VAL"; else printf '%s' "$UNSET"; fi; }
# matches NAME TARGET -> 0 if current state equals target
matches() {
  state "$1"
  if [ "$2" = "$UNSET" ]; then [ "$S_SET" -eq 0 ]; else [ "$S_SET" -eq 1 ] && [ "$S_VAL" = "$2" ]; fi
}
# put NAME TARGET
put() {
  if [ "$2" = "$UNSET" ]; then nvram unset "$1"; else nvram set "$1=$2"; fi
}
target_of() { _r=${1#*=}; printf '%s' "${_r%%|*}"; }

do_status() {
  snap
  echo "knob|current|target|match"
  bad=0
  while read -r line; do
    name=${line%%=*}
    tgt=$(target_of "$line")
    state "$name"
    cur=$(show)
    if matches "$name" "$tgt"; then m=ok; else m=DIFF; bad=$((bad + 1)); fi
    echo "$name|$cur|$tgt|$m"
  done < "$T/sel"
  echo "diff_count=$bad"
  [ "$bad" -eq 0 ]
}

case $cmd in
status)
  do_status
  exit $?
  ;;

apply)
  sw=$(nvram get sw_mode)
  re=$(nvram get re_mode)
  if [ "$sw" != "3" ] || [ "$re" = "1" ]; then
    echo "REFUSE: need sw_mode=3 and re_mode!=1 (have sw_mode=$sw re_mode=$re)" >&2
    exit 1
  fi
  if [ ! -d "${PREV%/*}" ] || [ ! -w "${PREV%/*}" ]; then
    echo "REFUSE: /jffs not writable (enable JFFS, cannot save undo data)" >&2
    exit 1
  fi
  snap
  [ -s "$T/snap" ] || { echo "REFUSE: empty 'nvram show'" >&2; exit 1; }
  # save previous values (first save wins)
  touch "$PREV" || exit 1
  chmod 600 "$PREV" 2>/dev/null
  saved=0
  while read -r line; do
    name=${line%%=*}
    if grep "^$name|" "$PREV" >/dev/null 2>&1; then continue; fi
    state "$name"
    if [ "$S_SET" -eq 1 ]; then echo "$name|S|$S_VAL" >> "$PREV"; else echo "$name|U|" >> "$PREV"; fi
    saved=$((saved + 1))
  done < "$T/sel"
  echo "prev_saved=$saved file=$PREV"
  changed=0
  while read -r line; do
    name=${line%%=*}
    tgt=$(target_of "$line")
    if matches "$name" "$tgt"; then continue; fi
    put "$name" "$tgt"
    changed=$((changed + 1))
  done < "$T/sel"
  if [ "$changed" -gt 0 ]; then nvram commit; fi
  echo "changed=$changed"
  do_status
  rc=$?
  echo "REBOOT REQUIRED: run 'reboot' for services to pick up changes"
  exit $rc
  ;;

revert)
  [ -s "$PREV" ] || { echo "REFUSE: no saved values at $PREV" >&2; exit 1; }
  snap
  changed=0
  : > "$T/keep"
  cp "$PREV" "$T/prevcopy"
  # restore selected knobs that have a saved entry; keep other entries
  while IFS='|' read -r name typ val; do
    [ -n "$name" ] || continue
    if grep "^$name=" "$T/sel" >/dev/null 2>&1; then
      if [ "$typ" = "S" ]; then want=$val; else want=$UNSET; fi
      if ! matches "$name" "$want"; then
        put "$name" "$want"
        changed=$((changed + 1))
      fi
    else
      echo "$name|$typ|$val" >> "$T/keep"
    fi
  done < "$T/prevcopy"
  if [ "$changed" -gt 0 ]; then nvram commit; fi
  if [ -s "$T/keep" ]; then cp "$T/keep" "$PREV"; else rm -f "$PREV"; fi
  echo "restored=$changed remaining_saved=$(wc -l < "$T/keep" | tr -d ' ')"
  echo "REBOOT REQUIRED: run 'reboot' for services to pick up changes"
  ;;
esac
