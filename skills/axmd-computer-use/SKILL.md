---
name: axmd-computer-use
description: >-
  Token-minimal macOS computer use through the Accessibility tree. Use when the
  user wants to read or click UI in a running macOS app (Safari, Chrome, native
  apps) without screenshots, needs headless clicks via AXPress, wants compact
  AX-tree snapshots or diffs, or wants a repetitive UI loop run cheaply. Don't
  use for plain web scraping where an HTTP request works, or when a browser
  DevTools/CDP tool is already attached to the target page.
---

# axmd computer use

`scripts/axmd.swift` is a single-file CLI. It prints an app's AX tree as one
line per element and acts on elements by index. Full page ≈3k tokens; grep,
diff or click ≈10–100 tokens.

## Setup

1. `swiftc -O scripts/axmd.swift -o scripts/axmd`
2. Verify: `scripts/axmd Finder` prints lines ending in a `(shown/visited)` footer.
3. Exit code 1 → the process running the agent's shell (terminal, IDE, agent
   app) lacks Accessibility permission. Ask the user to enable it in
   System Settings › Privacy & Security › Accessibility. Nothing else is needed.

## Output

`<idx> <role> "label" =value [flags] <url>`

Roles: `b` button · `l` link · `t` field · `c` checkbox · `r` radio · `p` popup ·
`m` menu item · `h` heading · `x` text · `tab` · `dlg`.
Flags: `sel foc off open on mixed`.

## Commands

| Goal | Command |
|---|---|
| Find one element | `axmd <app> --grep "<label>"` |
| Interactive elements + headings | `axmd <app> [--urls]` |
| Read page/content text | `axmd <app> --text --root webarea` |
| Changes since last snapshot | `axmd <app> --diff` |
| Click (no mouse) | `axmd <app> --press <idx>` |
| Set a field | `axmd <app> --type <idx> "<text>"` |
| Scope | `--root dialog\|webarea\|tabgroup\|toolbar`, `--window "<title>"` |

`<app>` = app name, bundle id or pid. Indices are valid only for the same
app/root/flags; resolve with `--grep` immediately before `--press`.

## Token discipline

The CLI is free. Cost is the agent context re-sent every turn; provider prompt
caching covers only the unchanged prefix.

1. Loops run as **one** shell process printing **one line per iteration**.
   Template: [loop.sh](scripts/loop.sh)
   (`APP=Safari REFRESH="Reload" ACTION="Open" N=3 scripts/loop.sh`).
2. Full dumps go to a file; inspect with `grep`, never paste into chat.
3. Prefer `--grep` → `--diff` → `--root` → full dump.
4. Token estimate when asked: bytes ÷ 4.

## Pitfalls

- One loop at a time. `loop.sh` holds a lock; don't start a second agent task.
- Abort when `--grep` finds nothing; never `--press` an empty index.
- Wait for content (poll for a `h "` line), not a fixed sleep.
- Bring the target tab/window to front before `--root webarea`, or the wrong
  tree is read.
- Web modals often aren't exposed as `dialog`; use `--grep`.
- `--urls` exposes link targets, often removing the need to click.
- Chromium: first call enables `AXManualAccessibility`; rerun if content is empty.

## Verify

After every `--press`, confirm the expected change with `--grep` or `--diff`.
For browsers, `osascript -e 'tell application "Safari" to get URL of current tab of window 1'`
is a cheap ground truth.
