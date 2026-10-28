# CLAUDE.md

This fork's `ap-stripdown` branch strips the GT-AX6000 firmware down for access-point-only use.

Read `stripdown-docs/HANDOFF.md` before acting: goal, constraints, CI build setup and next steps.

- This repo is public. Never commit secrets, PSKs, nvram dumps, MAC addresses, SSIDs or `/jffs` files.
- Never open upstream PRs or public issues for security findings. Ask the owner.
- The files in `stripdown-docs/` are redacted public copies. Some April docs stay with the owner.
- Paths such as `/var/tmp/...` and `/home/robert/...` in those docs are on the owner's machine, not in this
  environment.
