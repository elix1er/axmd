---
name: axmd-computer-use
description: >-
  Token-minimal macOS computer use through the Accessibility tree. Use when the
  user wants to read or click UI in a running macOS app (Safari, Chrome, native
  apps) without screenshots, needs headless clicks via AXPress, wants compact
  AX-tree snapshots or diffs, or wants a repetitive UI loop run cheaply. Don't
  use for plain web scraping where an HTTP request works, or when a browser
  DevTools/CDP tool is already attached to the target page.
metadata:
  short-description: Token-minimal macOS AX-tree snapshots & headless clicks
---

# axmd computer use

`<path-to-skill>/scripts/axmd.swift` walks a macOS app's `AXUIElement` tree via
batched IPC and prints one line per interactive element, acting on elements by
integer index. Full page ≈2.7k tokens; `--grep`, `--diff`, or `--press` ≈10–75 tokens.

## Setup & sandbox preflight

Set `AX=<path-to-skill>/scripts/axmd` (the directory containing this `SKILL.md`):

```bash
swiftc -module-cache-path "${TMPDIR:-/tmp}/axmd-module-cache" -O <path-to-skill>/scripts/axmd.swift -o "$AX"
"$AX" --help
```

- Using `-module-cache-path` avoids Swift `ModuleCache` write errors inside sandboxed agent shells (such as Codex).
- If running `"$AX" Finder` fails with exit code `1` or sandbox restrictions block `AXUIElement` IPC, rerun the command with escalated/unsandboxed permissions; if it still exits `1`, ask the user to enable the host app in **System Settings › Privacy & Security › Accessibility**.
- Exit codes: `0` ok · `1` no Accessibility permission · `2` missing `<app>` · `3` app not found · `4` no matching window · `5` `--root` not found · `6` `<idx>` out of range · `7` `AXPress`/`AXValue` failed.

## Output

`<idx> <role> "label" =value [flags] <url>`

Roles: `b` button · `l` link · `t` field · `c` checkbox · `r` radio · `p` popup ·
`m` menu item · `s` slider · `tab` · `h` heading · `x` text · `dlg` dialog.
Flags: `sel` · `foc` · `off` · `open` · `on` · `mixed`.

## Commands

| Goal | Command |
|---|---|
| Find one element | `"$AX" <app> --grep "<label>"` |
| Interactive elements + headings | `"$AX" <app> [--urls]` |
| Read page/content text | `"$AX" <app> --text --root webarea` |
| Changes since last snapshot | `"$AX" <app> --diff` |
| Click headless (no cursor move) | `"$AX" <app> --press <idx>` |
| Set a text field | `"$AX" <app> --type <idx> "<text>"` |
| Scope subtree | `--root dialog\|webarea\|tabgroup\|toolbar`, `--window "<title>"` |

`<app>` accepts app name, bundle ID, or PID. Indices apply only to the exact
`app + root + window + text` scope that produced them; resolve with `--grep`
immediately before `--press`.

## Token discipline

The CLI costs zero tokens; re-sending agent context every turn is what costs
money.

1. Run repetitive UI loops as **one** shell process printing **one summary line
   per iteration** to `stdout`. Template: [`scripts/loop.sh`](scripts/loop.sh)
   (`APP=Safari REFRESH="Reload" ACTION="Open" N=3 <path-to-skill>/scripts/loop.sh`).
2. Redirect full snapshots to a log file and query with `grep`; never dump raw
   trees into chat context.
3. Prefer `--grep` → `--diff` → `--root` → full snapshot.
4. Estimate tokens as `bytes ÷ 4`.

## Operational invariants & pitfalls

- **Single loop instance:** `loop.sh` uses a PID-checked lock (`$TMPDIR/axmd-loop.lock`)
  that auto-recovers from stale `SIGKILL` locks while blocking concurrent runs.
- **Stop condition on failure:** If `--grep` returns empty or `--press` exits `7`,
  abort immediately—never pass an empty index to `--press`.
- **Poll for content:** Poll `--text --root webarea` for a `h "` heading line
  (up to 6s) instead of relying on a fixed `sleep`.
- **Foreground the target tab:** Activate the target browser tab before running
  `--root webarea` so `axmd` reads the right document.
- **Web modals:** Many web modals do not expose `AXDialog`; locate buttons with
  `--grep` instead of `--root dialog`.
- **Link href shortcut:** `--urls` prints `<href>` targets directly on link
  nodes, often avoiding the need to click a link just to inspect its destination.
- **Chromium hydration:** `axmd` enables `AXManualAccessibility` automatically
  on first contact and skips the 150ms hydration sleep on subsequent calls.

## Verify

After every `--press` or `--type`, verify the expected state transition with
`--diff` or `--grep`. For browser navigation, check ground-truth tab state via
`osascript -e 'tell application "Safari" to get URL of current tab of window 1'`.
