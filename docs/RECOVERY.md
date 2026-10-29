# GT-AX6000 recovery (rescue mode)
fmt: machine-readable; k=v and pipe tables; tag SRC=url|REPO|UNVERIFIED per line that matters. date=2026-10-29
scope: restore official Merlin 3006.102.9 after bad flash / boot loop. Gate: PLAN.md P2.1/P2.2 (drill before any custom flash).

## 0.facts
device=GT-AX6000 soc=BCM4912 bootloader=u-boot(FIT .pkgtb per docs/gt-ax6000-ap-plan.md) SRC=REPO
restore_image=GT-AX6000_3006_102.9_0_nand_squashfs.pkgtb (inside GT-AX6000_3006_102.9_0.zip; unzip first, rescue tools take the raw file) SRC=REPO(.github/workflows/compare-official.yml)
restore_url=https://sourceforge.net/projects/asuswrt-merlin/files/GT-AX6000/Release/GT-AX6000_3006_102.9_0.zip/download SRC=REPO
restore_sha256_pkgtb=f64453852fb3eacb996978cc2c0abc505e744c7a9a3a4522f0a98866e2c7a7e0 (zip=66648301B pkgtb=70438392B) SRC=REPO(docs/baseline-3006.102.9-ci-vs-official.md)
verify_cmd=sha256sum GT-AX6000_3006_102.9_0_nand_squashfs.pkgtb | grep -q f64453852fb3eacb996978cc2c0abc505e744c7a9a3a4522f0a98866e2c7a7e0 && echo OK
pc_ip=192.168.1.10 mask=255.255.255.0 gateway=none SRC=https://www.asus.com/support/faq/1000814/
rescue_ip=192.168.1.1 SRC=UNVERIFIED (ASUS FAQ gives PC side only; SNB reports mixed 192.168.1.1 vs 192.168.50.1 for newer models -> test both)
web_fetch_note=asus.com and snbforums.com were not reachable from the authoring sandbox; ASUS steps below come from search-result summaries of FAQ 1000814 / 1030652, not a page read. Re-read on a networked machine before the drill.

## 1.before_any_flash (do first)
step|action|cmd_or_where|pass
b1|download official zip + verify sha256 of the .pkgtb|see 0.verify_cmd|prints OK
b2|keep on the PC: unzipped pkgtb + ASUS Firmware Restoration utility (Windows) + a tftp client|ASUS support page for GT-AX6000 > Utilities (SRC=UNVERIFIED exact download path)|files local, offline-usable
b3|settings backup via GUI|Administration > Restore/Save/Upload Setting > Save setting (Settings_GT-AX6000.CFG)|file saved off-router
b4|jffs backup (scripts, ap-harden.prev, custom configs)|ssh: `tar czf /tmp/jffs.tgz -C /jffs .` then on PC `scp -O admin@<ap>:/tmp/jffs.tgz .` (use -O if sftp subsystem absent; dropbear)|tgz on PC, `tar tzf` lists files
b5|nvram dump for reference (contains secrets: keep private)|ssh: `nvram show 2>/dev/null > /tmp/nvram.txt` then scp|file on PC
b6|runtime baseline|`sh tools/ap-baseline.sh pre-flash` (scp dir off router)|dir on PC
b7|`nvram save`/`nvram restore` as raw backup|SRC=UNVERIFIED whether this build's nvram applet supports save/restore; use b3 + b5 instead|-
b8|cable PC to a LAN port (not WAN; not wifi), disable PC wifi, stop VPN/firewall blocking UDP/69|-|-
b9|know ethernet adapter name for static IP change|PC|-

## 2.rescue_mode_entry
step|action|expect|SRC
r1|power off router (pull DC)|all LEDs off|-
r2|hold Reset (hole button) ~5 s, reconnect power while still holding|-|https://www.asus.com/support/faq/1030652/
r3|release Reset when power LED starts flashing|power LED flashes|https://www.asus.com/support/faq/1000814/
r4|confirm rescue mode: power LED SLOW flash|slow blink = rescue mode|https://www.asus.com/support/faq/1000814/
r5|if LED does nothing: repeat r1-r4 holding longer; ASUS also says "keep holding until rescue mode is on"|-|https://www.asus.com/support/faq/1000814/
note_GT-AX6000_specific=LED pattern and hold time for this model UNVERIFIED (generic ASUS procedure). Other LEDs (AURA/RGB) may differ.
pc_setup=set adapter IPv4 static 192.168.1.10/255.255.255.0 BEFORE r1; no DNS/gateway needed; revert to DHCP after recovery SRC=https://www.asus.com/support/faq/1000814/

## 3.method_A_ASUS_Firmware_Restoration (Windows XP/7/8/10/11 per ASUS)
step|action|expect
a1|rescue mode active (section 2), PC 192.168.1.10|ping 192.168.1.1 answers (SRC=UNVERIFIED target ip)
a2|run Firmware Restoration, Browse -> raw .pkgtb (not the zip), Upload|upload progress
a3|wait ~60 s without touching power|ASUS: steady power LED = success SRC=https://www.asus.com/support/faq/1000814/
a4|wait for full reboot (several min), set PC back to DHCP|-
a5|open https://router.asus.com or http://192.168.50.1 (default after reset) SRC=UNVERIFIED for this model|login page
a6|if GUI will not load: reset button press then repeat method A (ASUS suggestion) SRC=https://www.asus.com/support/faq/1000814/
known_issue=SNB threads report Restoration utility failing on GT-AX6000; one user succeeded via the browser page at the rescue IP (raw file). SRC=UNVERIFIED (search summaries of https://www.snbforums.com/threads/gt-ax6000-rescue.88572/)

## 4.method_B_rescue_web_page
b1|rescue mode active, PC 192.168.1.10|-
b2|browse http://192.168.1.1 (also try http://192.168.50.1)|ASUS rescue upload page SRC=UNVERIFIED
b3|choose raw .pkgtb, upload, wait for reboot|steady power LED
b4|if browser reports connection error after upload: try another browser, wired only, disable PC proxy|-

## 5.method_C_tftp_fallback
status=UNVERIFIED for GT-AX6000 (one SNB user reports TFTP timeouts; procedure is from older ASUS CFE models)
c1|rescue mode active, PC 192.168.1.10, tftp client installed|-
c2|binary mode, put to router: `tftp -i 192.168.1.1 PUT GT-AX6000_3006_102.9_0_nand_squashfs.pkgtb` (Windows: `tftp -i 192.168.1.1 PUT <file>`; Linux tftp-hpa: `tftp 192.168.1.1 -c put <file>` after `-m binary`)|transfer completes, router reboots after ~min
c3|retry once within ~10 s of rescue LED start; some loaders accept TFTP only briefly after boot|SRC=UNVERIFIED
c4|if timeouts: stop, use method A/B or UART (section 8)|-

## 6.nvram_reset (after restore, or when settings corrupt but fw boots)
method|steps|SRC
gui|Administration > Restore/Save/Upload Setting > Factory default (+ tick "initialize all settings" if present)|UNVERIFIED label text
reset_button|router on, hold Reset ~5-10 s until power LED blinks, release|https://www.asus.com/kh/support/faq/1039077/ (ASUS hard factory reset, method list; pick the one matching GT-AX6000: UNVERIFIED which)
wps_at_poweron|power off; hold WPS button; power on while holding; keep holding until LED behaviour in the ASUS method changes (variants: release when power LED goes off / when it flashes); release|https://www.asus.com/kh/support/faq/1039078 and https://www.asus.com/sg/support/faq/1046973/ (variant per model: UNVERIFIED for GT-AX6000)
ssh_erase|`mtd-erase -d nvram` then `reboot`|UNVERIFIED on this build; nvram is rewritten from RAM on reboot on some builds, so power-cut right after erase
after_reset=default LAN 192.168.50.1 (UNVERIFIED), sw_mode back to router(1): re-set Administration > Operation Mode > Access Point; re-import b3 CFG only if same fw version family; jffs may survive reset (UNVERIFIED) -> restore b4 if empty
after_reset_check=`nvram get sw_mode` =3, `nvram get re_mode` =0 before running ap-harden.sh apply

## 7.dual_image
GT-AX6000 u-boot may keep two firmware slots and fall back after failed boots; UNVERIFIED. Do NOT rely on it. Always have sections 3-5 ready.

## 8.uart_last_resort (UNVERIFIED section)
need=USB-UART 3.3V TTL (never 5V/RS232), dupont wires, soldering iron if header unpopulated
params=115200 8N1 no flow control (typical BCM HND; UNVERIFIED for this unit)
header=location and pinout on GT-AX6000 board: UNVERIFIED (no sourced pinout; identify GND/TX/RX with multimeter: GND to shield, TX idles ~3.3V). Do not connect VCC.
use=interrupt u-boot at power-on (key sequence UNVERIFIED), inspect env, load image over TFTP from u-boot (`tftpboot`/`setenv ipaddr`/`setenv serverip` style commands UNVERIFIED for this u-boot build)
risk=wrong wiring can kill board; do only if A/B/C all fail

## 9.drill_record (PLAN.md P2.2)
fields: date|image_sha256_verified|method(A/B/C)|rescue_ip_seen|led_pattern_seen|minutes_to_gui|result
rows: (none yet)

## 10.sources
https://www.asus.com/support/faq/1000814/ rescue mode + Firmware Restoration (via search summary)
https://www.asus.com/support/faq/1030652/ firmware upgrade failed (hold reset ~5 s at power-on, release when LED flashes)
https://www.asus.com/kh/support/faq/1039077/ , https://asus.com/kh/support/FAQ/1039078 , https://www.asus.com/sg/support/faq/1046973/ hard factory reset methods
https://www.snbforums.com/threads/gt-ax6000-rescue.88572/ , https://www.snbforums.com/threads/asus-gt-ax6000-stuck-in-boot-loop-after-firmware-upgrade.96243/ , https://www.snbforums.com/threads/booting-problem-gt-ax6000.97480/ (user reports; not read)
https://chrishardie.com/2013/02/asus-router-firmware-windows-mac-linux/ (older-model TFTP/non-Windows rescue; not read)
