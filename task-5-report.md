# Task 5 report: build once, no push trigger

Done. Branch `ci-build-once`, commit `e105e7a487` "ci: build only on dispatch, once per change (no build on push)". PR (draft not required, not merged): https://github.com/bottobot/asuswrt-merlin.ng/pull/9

Changes: removed the `push:` block (3 lines) from build-gt-ax6000.yml, added the comment above `on:`, kept workflow_dispatch/ref input; PLAN.md: `ci_rule=` line after `ci=` and `ci=` now says "dispatch-only"; workflow comment "empty on push and when not given on dispatch" -> "empty when not given on dispatch" (the grep matched "on push"). Left PLAN.md:39 (P0.3 DONE row mentioning paths-ignore) as historical record. compare-official.yml and release.yml untouched (release.yml still accepts push or dispatch events, so dispatch builds qualify). README/docs/tools had no false statements per the grep. No build dispatched.

Verified: YAML parses; `on` keys = workflow_dispatch only.

## Grep before changes
```
PLAN.md:39: ...paths-ignore docs/**...
.github/workflows/build-gt-ax6000.yml:15:    paths-ignore: [...]
.github/workflows/build-gt-ax6000.yml:45:  INPUT_REF ... # empty on push and when not given on dispatch
```
## Diff
```diff
diff --git a/.github/workflows/build-gt-ax6000.yml b/.github/workflows/build-gt-ax6000.yml
index c399409a0a..7d911f2f64 100644
--- a/.github/workflows/build-gt-ax6000.yml
+++ b/.github/workflows/build-gt-ax6000.yml
@@ -2,6 +2,7 @@ name: build-gt-ax6000
 
 # Builds GT-AX6000 firmware from this branch in gnuton's Merlin toolchain container.
 # Recipe: RMerl tools/build-all (SDK src-rt-5.04axhnd.675x, `make gt-ax6000`) + gnuton's CI layout.
+# Builds run only when dispatched, once per change; merges do not rebuild (Actions was paused 2026-10-29 for usage scale).
 on:
   workflow_dispatch:
     inputs:
@@ -10,9 +11,6 @@ on:
         required: false
         default: ''
         type: string
-  push:
-    branches: [ap-stripdown]
-    paths-ignore: ['**.md', 'docs/**', 'tools/ap-*.sh']
 
 concurrency:
   group: build-${{ github.ref }}
@@ -42,7 +40,7 @@ jobs:
           ls /home/docker/am-toolchains/brcm-arm-hnd/ | grep -i 9.2
       - name: Clone this branch
         env:
-          INPUT_REF: ${{ inputs.ref }}   # empty on push and when not given on dispatch
+          INPUT_REF: ${{ inputs.ref }}   # empty when not given on dispatch
         run: |
           chown docker /project
           REF="${INPUT_REF:-$GITHUB_REF_NAME}"
diff --git a/PLAN.md b/PLAN.md
index 70c884f8f3..f427c70b88 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -2,7 +2,8 @@
 fmt: machine-readable. task=`ID|tier|min|dep|status|action|done_when`. tier: H=haiku S=sonnet O=opus(review/gate only) U=owner(hardware, cannot delegate). min<=20; overrun => split in place, never continue. status: DONE|WIP|TODO|BLOCKED(reason).
 facts_ref=docs/gt-ax6000-ap-plan.md (investigation: service inventory, flags, CVEs). baseline_ref=docs/baseline-3006.102.9-ci-vs-official.md. this file=single source for WHAT/ORDER/STATUS; v1 superseded.
 base=Merlin 3006.102.9 (3006.102-wifi6 @c73015d). sdk=release/src-rt-5.04axhnd.675x make=gt-ax6000. flags=release/src-rt/target.mak:197-221. flag->RTCONFIG+forced deps=release/src-rt/Makefile. pkg gating=release/src/router/Makefile. rc=release/src/router/rc/{services,watchdog,lan,wan}.c.
-ci=.github/workflows/build-gt-ax6000.yml (root container, clone+make as docker, MERLINUPDATE=y, digest-pinned, 45-63min). cloud sandbox: no build (no toolchain/docker/disk), artifact download blocked (blob 403) => all image work runs in CI.
+ci=.github/workflows/build-gt-ax6000.yml (root container, clone+make as docker, MERLINUPDATE=y, digest-pinned, 45-63min, dispatch-only). cloud sandbox: no build (no toolchain/docker/disk), artifact download blocked (blob 403) => all image work runs in CI.
+ci_rule=build each change once: dispatch build-gt-ax6000 on the PR branch only when the PR is ready (ref=<branch>); after a red build fix every error that log shows before dispatching again; merge without rebuilding (no push trigger since 2026-10-31); a release needs one dispatch on the tag commit (release.yml requires a successful build of that exact commit)
 
 ## 1.CRITIQUE (v1 PLAN.md + docs/gt-ax6000-ap-plan.md §6)
 C1|v1 E2 WRONG|on Broadcom `access_point_mode()`=sw_mode==3&&!wlc_psta (shared/shared.h:2074); does NOT exclude re_mode. v1 rule "use access_point_mode() to cover re_mode" false.
```
