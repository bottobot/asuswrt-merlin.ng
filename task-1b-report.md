# Task 1b report: MERLINUPDATE=y in CI build

Commit `55c9f3acac` "ci: build with MERLINUPDATE=y like the official release" on ap-stripdown; only `.github/workflows/build-gt-ax6000.yml` (+2): `env: MERLINUPDATE: y` on the Build step with a comment pointing at docs/baseline-3006.102.9-ci-vs-official.md. Pushed. New run id **40690847523** (head 55c9f3acac), in_progress; not waited on.

## Comparison script (sandbox only, not committed): /tmp/t2/compare.sh <run-id>
Downloads the run's `gt-ax6000-*` artifact via `gh api .../artifacts/<id>/zip`, extracts rootfs with `dumpimage -T flat_dt -p 1` (FIT image 1 = nand_squashfs) and `unsquashfs -no-xattrs`, into /tmp/t2/x/<run-id>/rootfs, then compares against official (/tmp/t2/x/off/rootfs) and run #2 CI (/tmp/t2/x/ci/rootfs): entries only on one side, mode/type diffs, symlink diffs, regular files whose sha256 differ (lists in /tmp/t2/changed.{off,ci}.txt).
Note: /tmp/t2 did not exist in this sandbox, so I recreated it: tools installed via apt (squashfs-tools, device-tree-compiler, u-boot-tools); official zip from SourceForge (sha256 of pkgtb f64453852f... matches); run 40640600800 artifact (pkgtb sha256 072db7cf...) as `ci`.

## Test on run 40683951523 (pkgtb sha256 baa7ca64...)
- vs run #2 CI: 3940 entries both, no path/mode/symlink differences; 18 regular files differ: busybox, modules.dep, rom/etc/image_version, rom/etc/motd, libcrypto, libgcrypt, libgdbm, liblldpcli/lldpd/lldpcli, libshared, chilli_opt, lighttpd, miniupnpd(+igdv2), openvpn, socat, stubby. Samples: busybox 18 bytes of 527436 differ, libcrypto 5 of 4.48M, lldpd 5 of 143500, libshared 12 of 767584 (build-id/timestamp); image_version build number 3010657 vs 3011241; motd and "Built on" strings are timestamps; modules.dep is line-order only. Verdict: noise only.
- vs official (expected, pre-MERLINUPDATE): 82 files differ, `usr/sbin/webs_upgrade.sh` only in CI, kernel module source-path dirs differ (build dir /project/src vs workspace/build/amng.gtax6000), 53 mode diffs. Run `compare.sh 40690847523` after CI to confirm these shrink.

## Unverified
New run's result. Mode-diff cause (53) not inspected here.
