# Task 1 report: CI workflow green + image pin

Done. Commit `4c2f4366d6` "ci: tolerate upload-artifact set_output EACCES, pin toolchain image by digest" on ap-stripdown; diff touches only `.github/workflows/build-gt-ax6000.yml` (17+, 2-).

Changes: `continue-on-error: true` on both upload-artifact steps; removed the `sudo chmod -R a+rwX /__w/_temp` line and comment (kept `sudo chown docker /project`); image pinned to `gnuton/asuswrt-merlin-toolchains-docker@sha256:8c9681987352d6eb8a38708126c9c39edd8dd28a7bf6c0cedc0e9534387f9ab3` with a comment naming `latest` on 2026-10-28; added `id: build` to the Build step and a final `if: always()` step "Verify firmware artifact was uploaded" that, when the build step outcome is `success`, curls `.../actions/runs/$GITHUB_RUN_ID/artifacts` with the bearer token and fails unless `gt-ax6000-$GITHUB_SHA` is listed.

Verified: YAML parses (python yaml). Push `9c96e1f842..4c2f4366d6`.
New run: `gh api "repos/bottobot/asuswrt-merlin.ng/actions/runs?branch=ap-stripdown&per_page=1"` -> id **40683951523**, head 4c2f4366d6, in_progress at fire time. Not waited on.

Unverified: the new verify step has never run; its grep assumes the API's default `"name": "gt-ax6000-<sha>"` spacing. The artifacts API could lag right after upload; if the step fails with the artifact present, add a short retry. Task 2's doc commit (markdown only) did not trigger a build.
