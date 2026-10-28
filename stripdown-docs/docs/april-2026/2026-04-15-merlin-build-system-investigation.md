# Merlin Build System Config Generation — Deep Investigation

**Date:** 2026-04-15
**Context:** GT-AX6000 stripped firmware build on branch `security/stripped-ap-build`
**Problem:** Disabled features get re-enabled during build, causing compilation failures against deleted source directories

---

## 1. The Config Generation Pipeline

When you run `make gt-ax6000`, the config is generated in this order:

```
target.mak (make variables)
       |
       v
config_base (static baseline, copied to config_gt-ax6000)
       |
       v
RouterOptions() (Makefile function, ~5000 lines, reads target.mak variables, 
                  uses sed -i to overwrite values in config_gt-ax6000)
       |
       v
config_gt-ax6000 (GENERATED - never edit manually)
       |
       v  (setprofile copies it)
.config (GENERATED - never edit manually)
```

### Key Makefile locations:
- `release/src-rt-5.04axhnd.675x/Makefile` line **80**: loads `.config`
- Line **1541**: `RouterOptions` function definition starts (~5000 lines of shell sed commands)
- Line **7026**: `bin` target — calls `cp router/config_base router/config_$(lowercase_B)`
- Line **7196**: calls `$(call RouterOptions, router/config_$(lowercase_B))`
- Line **7351**: `setprofile` — `cp config_current .config`

### Critical Rule
**`config_gt-ax6000` is ALWAYS regenerated from `config_base` + `RouterOptions`.** Manual edits to `config_gt-ax6000`, `.config`, or `rtconfig.h` are OVERWRITTEN every build.

**`target.mak` is the ONLY source of truth.** All feature flags must be set/unset there.

---

## 2. Auto-Enabled Flag Cascades

The `RouterOptions` function auto-enables child flags when parent flags are `y`. These cascades are the root cause of features reappearing.

### Cascade Map (parent → auto-enabled children)

| Parent Flag | Auto-Enabled Children | Makefile Lines |
|-------------|----------------------|----------------|
| `CONNDIAG=y` | LIB_CODB, NEW_PHYMAP, DNS_PING, CABLEDIAG | 2218-2237 |
| `AMAS=y` | CFGSYNC, MASTER_DET, ADV_RAST, LIBASUSLOG, ETHOBD, DWB, WLCEVENTD, DBLOG | ~4050-4070 |
| `BWDPI=y` | NOTIFICATION_CENTER | (in RouterOptions) |
| `CAPTIVE_PORTAL=y` | COOVACHILLI, CP_FREEWIFI | 3627-3631 |
| `PARENTAL2=y` | PARENTALCTRL, CONNTRACK, PC_REWARD, SCHED_DAEMON | (in RouterOptions) |
| `BCN_RPT=y + CONNDIAG=y` | MC_BCN_RPT, 11K_RCPI_CHECK, NBR_RPT | (in RouterOptions) |
| `SW_CTRL_ALLLED=y` | LED_SCHED | (in RouterOptions) |
| `ASD=y` | LIBASC | (in RouterOptions) |
| `TIMEMACHINE=y` | MDNS (forced) | (in RouterOptions) |
| `OPENVPN=y` | LZO | (in RouterOptions) |
| `DWB=y` (standalone) | RTCONFIG_DWB | 4408-4411 |

### HND-94912_BASE inherited flags (line 197-198):
```
AMAS=y UTF8_SSID=y ETHOBD=y DWB=y CONNDIAG=y
```
These are inherited by ALL 94912 models. Override in GT-AX6000 `+=` section — do NOT modify the base.

---

## 3. Complete Error Analysis

### Error: `openvpn_config.h: No such file or directory`
- **File:** `release/src/router/httpd/sysinfo.c` line 83
- **Cause:** **SOURCE CODE BUG** — `#include "openvpn_config.h"` is UNCONDITIONAL (no `#ifdef RTCONFIG_OPENVPN` guard)
- **Compare:** `web.c` line 112-116 HAS proper `#ifdef RTCONFIG_OPENVPN` guards for the same header
- **Fix:** Add `#ifdef RTCONFIG_OPENVPN` / `#endif` around line 83 in sysinfo.c

### Error: `amas_dwb.h: No such file or directory`
- **File:** `release/src/router/rc/init.c` lines 104-106
- **Cause:** Properly guarded by `#if defined(RTCONFIG_DWB)`, but `DWB=y` is still set in target.mak
- **Fix:** Set `DWB=n` in target.mak GT-AX6000 section
- **Note:** `amas_dwb.h` exists at `release/src/router/shared/sysdeps/amas/amas_dwb.h` — it wasn't deleted, but requires AMAS headers to function

### Error: `sqlite3.h: No such file or directory` (from conn_diag-sql.h)
- **File:** `release/src/router/rc/rc.c` lines 42-44, guarded by `#if defined(RTCONFIG_CONNDIAG)`
- **Cause:** `CONNDIAG=y` still in target.mak → auto-enables LIB_CODB → conn_diag-sql.h → sqlite3.h
- **Fix:** Set `CONNDIAG=n` in target.mak

### Error: `'RAST_EVENT_ID' undeclared`
- **File:** `release/src/router/rc/rc.c` line 1735-1747, guarded by `#if defined(RTCONFIG_CONNDIAG)`
- **Cause:** Same as above — CONNDIAG still enabled
- **Fix:** Set `CONNDIAG=n`

### Error: `'cr_en' undeclared`
- **File:** `release/src/router/rc/services.c` line 12197
- **Cause:** Inside `#if defined(RTCONFIG_CAPTIVE_PORTAL)` block; `CAPTIVE_PORTAL=y` still in target.mak
- **Fix:** Set `CAPTIVE_PORTAL=n` and `CP_FREEWIFI=n`

### Error: syntax errors in lan.c (lines 442, 6106)
- **Cause:** Related to `RTCONFIG_PROXYSTA` removal — `psta_exist_except()` function undefined when PROXYSTA disabled, but code paths still reference it under `CONFIG_BCMWL5` which remains enabled
- **Note:** Our `is_psta`/`is_psr` stubs in misc.c help, but lan.c has additional PROXYSTA-dependent code patterns. The `#ifdef RTCONFIG_PROXYSTA` blocks in lan.c may have dangling `||` operators when the flag is removed.
- **Fix:** Need to verify — may need additional stubs or the PROXYSTA flag may need to stay enabled (it controls proxy STA mode but doesn't add significant attack surface as it's a wireless driver feature, not a network service)

---

## 4. Complete target.mak Changes Required

### Flags that MUST be `=n` in GT-AX6000 section:

**Already changed (commit de8e459aed):**
```
AMAS=n  OPENVPN=n  VPNC=n  VPN_FUSION=n  VPN_FUSION_MERLIN=n
WIREGUARD=n  IPSEC=n  IPSEC_SRVCLI_ONLY=n  INSTANT_GUARD=n
ACCEL_PPTPD=n  REPEATER=n  PROXYSTA=n  MEDIASRV=n  MODEM=n
NATNL_AICLOUD=n  NATNL_AIHOME=n  ALEXA=n  GOOGLE_ASST=n  EMAIL=n
```

**MUST ALSO change (currently `y`, causing build failures):**
```
CONNDIAG=n       # Prevents LIB_CODB, DNS_PING, RAST_EVENT_ID, conn_diag-sql.h cascades
DWB=n            # Prevents amas_dwb.h include
CAPTIVE_PORTAL=n # Prevents sqlite3.h, cr_en, COOVACHILLI cascades
CP_FREEWIFI=n    # Companion to CAPTIVE_PORTAL
WTFAST_V2=n      # Cloud gaming service, not needed
```

**SHOULD also change (reduce attack surface, prevent unnecessary deps):**
```
ETHOBD=n         # Ethernet OBD, only useful with AMAS
DBLOG=n          # Debug logging, AMAS companion
INFO_EXAP=n      # External AP info, AMAS feature
BCN_RPT=n        # 802.11k beacon reports (depends on CONNDIAG cascade)
BTM_11V=n        # 802.11v BSS transition (roaming, not needed for single AP)
ASD=n            # ASUS Security Daemon (prevents LIBASC auto-enable)
TIMEMACHINE=n    # Apple Time Machine (USB backup, not needed)
DISK_MONITOR=n   # USB disk monitoring
PRINTER=n        # USB printer sharing
```

**RECONSIDER disabling (may cause more issues than they solve):**
```
PROXYSTA         # Consider keeping =y — disabling causes lan.c syntax errors
                 # and the is_psta/is_psr stubs may not be sufficient.
                 # PROXYSTA is a wireless driver feature, not a network service.
```

### Source code fixes still needed:
1. `httpd/sysinfo.c` line 83: Add `#ifdef RTCONFIG_OPENVPN` guard around `#include "openvpn_config.h"`

---

## 5. The Right Way to Disable Features (Summary)

1. **ONLY modify `target.mak`** — set flags to `=n` in the GT-AX6000 export line
2. **NEVER manually edit** `config_gt-ax6000`, `.config`, or `rtconfig.h` — they are regenerated
3. **For inherited base flags** (from HND-94912_BASE): override with `=n` in the GT-AX6000 `+=` line
4. **For source code bugs** (unconditional includes): fix in the source with `#ifdef` guards
5. **For cascade flags** (auto-enabled children): disable the PARENT in target.mak; children auto-disable
6. **Delete source directories** only for features whose config flag is PERMANENTLY disabled in target.mak
7. **Create stub Makefiles/directories** for features where the build system has hard-coded `obj-y` references (like libcodb)

---

## 6. Key File Paths Reference

| File | Purpose |
|------|---------|
| `release/src-rt-5.04axhnd.675x/target.mak:197-221` | GT-AX6000 master config (THE source of truth) |
| `release/src-rt-5.04axhnd.675x/Makefile:1541` | RouterOptions function (config generation) |
| `release/src-rt-5.04axhnd.675x/Makefile:7026` | `bin` target (copies config_base → config_gt-ax6000) |
| `release/src-rt-5.04axhnd.675x/Makefile:7196` | RouterOptions invocation |
| `release/src-rt-5.04axhnd.675x/Makefile:7351` | setprofile (copies config → .config) |
| `release/src/router/config_base` | Baseline config (DO NOT EDIT for feature disable) |
| `release/src/router/httpd/sysinfo.c:83` | Unconditional openvpn_config.h include (BUG) |
| `release/src/router/rc/init.c:104` | DWB-guarded amas_dwb.h include |
| `release/src/router/rc/rc.c:42` | CONNDIAG-guarded conn_diag-sql.h include |
| `release/src/router/rc/services.c:12197` | CAPTIVE_PORTAL-guarded cr_en code |
