# asuswrt-merlin.ng — a personal strip-down experiment (GT-AX6000, AP mode)

> **⚠️ Do not use this firmware if you need a secure or reliable router.**
> This is one person learning and experimenting. Nothing here has been audited,
> nothing here is supported, and any build from this repository may break your
> device, weaken its security, or both. If you want a well-maintained firmware for
> your ASUS router, use the official
> [Asuswrt-Merlin](https://github.com/RMerl/asuswrt-merlin.ng) releases instead.

## What this is

[Asuswrt-Merlin](https://www.asuswrt-merlin.net/), by Eric Sauvageau (RMerl) and its
contributors, is careful work that has kept ASUS routers maintained and improved
for years. This fork is not an attempt to improve on it. It is me hacking away at
the edges of something that already works very well, to make it fit one narrow use.

This fork is not affiliated with Asuswrt-Merlin or ASUS. Please do not take problems
found here to the Merlin forums or issue tracker. Any problem in this fork is far
more likely to be mine than theirs.

## Why

I run a GT-AX6000 purely as a wireless access point behind a separate firewall. In
that role, the stock firmware still starts and listens for services an access point
does not need. Some examples, observed on my own device:

- ASUS device discovery (`infosvr`, UDP 9999), which has a history of vulnerabilities
- WAN detection (`wanduck`, TCP 18017 / UDP 18018), with no WAN in AP mode
- AiMesh configuration sync (`cfg_server`, port 7788), with no mesh
- mDNS/Bonjour advertising (`avahi`, UDP 5353), plus various ASUS cloud and telemetry helpers

My goal is to switch off or compile out what an access point does not use, and keep
what it does: both radios, VLAN-tagged guest networks (Guest Network Pro), the web
interface and SSH administration. In short, a smaller attack surface without
breaking the device.

## How

- Each change is a small, reviewable commit on top of a tagged Merlin release
  (currently **3006.102.9**, from the `3006.102-wifi6` branch that RMerl builds the GT-AX6000
  release from). It never rewrites upstream history.
- Firmware is built in GitHub Actions, never by hand. Before any change goes in, the
  first goal is to build unmodified 3006.102.9 in CI and check it against the
  official image. A byte-for-byte match is not expected, because builds embed
  timestamps and build details, so the check unpacks both images and compares
  their contents. Every later difference can then be traced to a commit here.
- Builds will be tested on hardware I can afford to brick before they go anywhere near
  a network anyone depends on.

## Status

Early. Nothing is stripped yet, and no build from this repository is recommended
for anyone, including me.

## Branches

- `ap-stripdown`: default branch. Merlin 3006.102.9 (`3006.102-wifi6` at
  `c73015d`) plus this README, the CI workflow and the strip-down work.
- `main` and the other upstream branches: untouched mirrors of
  [RMerl/asuswrt-merlin.ng](https://github.com/RMerl/asuswrt-merlin.ng).

## Licence

Everything inherits the licensing of Asuswrt-Merlin and Asuswrt: GPL for the open
components, and their own terms for the proprietary ASUS and Broadcom binaries. See
`License` and `README.proprietary`. The original project README is kept as
[`README-upstream.md`](README-upstream.md).
