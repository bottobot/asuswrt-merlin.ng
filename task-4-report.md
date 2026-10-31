# Task 4: P6.4 httpd upstream fixes (PR #8)

PR: https://github.com/bottobot/asuswrt-merlin.ng/pull/8 (branch p6.4-httpd-fixes -> ap-stripdown, not merged)

Commands: fetch ap-stripdown (c48f879), branch, add upstream remote, `git fetch --depth=2 upstream e0470de0b3 f382a51904`, `git cherry-pick -x` each.
Both picks: "Auto-merging ...httpd.c / web.c", no conflicts. Authorship/messages kept (Eric Sauvageau), no Co-Authored-By.

`git diff origin/ap-stripdown --stat` (after picks): release/src/router/httpd/httpd.c | 29 ; release/src/router/httpd/web.c | 10 ; only those two files.
The httpd.c hunks include a new `#ifdef RTCONFIG_HTTPS` block (upstream's own); no resolved hunks, so nothing in a compiled-out feature was hand-edited. Not verified whether RTCONFIG_HTTPS is on for GT-AX6000 (expected yes).

Commits: 2e65ffa8a5 httpd: don't stall on idle TLS connections; d7c5345e21 httpd: fix three memory leaks in get_multifilter_info()...; then PLAN commit (P6.4 DONE, decision text) and a follow-up filling PR #8.

BLOCKED part: build dispatch. `gh api -X POST .../actions/workflows/build-gt-ax6000.yml/dispatches -f ref=p6.4-httpd-fixes` -> HTTP 422 "Actions has been disabled for this repository." The branch push also started no run. So no CI run id; the change is NOT build-verified. Owner must re-enable Actions (Settings > Actions) and dispatch.
