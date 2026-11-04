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

`scripts/axmd.swift` walks a macOS app's `AXUIElement` tree via batched IPC and
prints one line per interactive element, acting on elements by integer index.
Full page ≈2.7k tokens; `--grep`, `--diff`, or `--press` ≈10–75 tokens.

## Setup

1. Build: `make` (at repo root) or `swiftc -O scripts/axmd.swift -o scripts/axmd`
   (or `make universal` for a stripped `arm64 + x86_64` fat binary).
2. Smoke check: `scripts/axmd --help` (exits `0`, prints usage).
3. Live check: `scripts/axmd Finder` prints indexed lines ending in `(shown/visited)`.
4. Exit codes:
   - `0` — ok
   - `1` — host process lacks Accessibility permission (enable the terminal/IDE
     in System Settings › Privacy & Security › Accessibility)
   - `2` — missing `<app>` argument
   - `3` — app not found
   - `4` — no matching window
   - `5` — `--root` role/subrole not found in window
   - `6` — `<idx>` out of range
   - `7` — `AXPress` / `AXValue` action failed

## Output

`<idx> <role> "label" =value [flags] <url>`

Roles: `b` button · `l` link · `t` field · `c` checkbox · `r` radio · `p` popup ·
`m` menu item · `s` slider · `tab` · `h` heading · `x` text · `dlg` dialog.
Flags: `sel` · `foc` · `off` · `open` · `on` · `mixed`.

## Commands

| Goal | Command |
|---|---|
| Find one element | `axmd <app> --grep "<label>"` |
| Interactive elements + headings | `axmd <app> [--urls]` |
| Read page/content text | `axmd <app> --text --root webarea` |
| Changes since last snapshot | `axmd <app> --diff` |
| Click headless (no cursor move) | `axmd <app> --press <idx>` |
| Set a text field | `axmd <app> --type <idx> "<text>"` |
| Scope subtree | `--root dialog\|webarea\|tabgroup\|toolbar`, `--window "<title>"` |

`<app>` accepts app name, bundle ID, or PID. Indices apply to the exact
`app + root + window + text` scope that produced them; resolve with `--grep`
immediately before `--press`.

## Token discipline

The CLI costs zero tokens; re-sending agent context every turn is what costs
money.

1. Run repetitive UI loops as **one** shell process printing **one summary line
   per iteration** to `stdout`. Template: [loop.sh](scripts/loop.sh)
   (`APP=Safari REFRESH="Reload" ACTION="Open" N=3 scripts/loop.sh`).
2. Redirect full snapshots to a log file and query with `grep`; never dump raw
   trees into chat context.
3. Prefer `--grep` → `--diff` → `--root` → full snapshot.
4. Estimate tokens as `bytes ÷ 4`.

## Pitfalls

- **Single loop instance:** `loop.sh` uses a PID-checked lock (`$TMPDIR/axmd-loop.lock`)
  that auto-recovers from stale `SIGKILL` locks while blocking concurrent runs.
- **Abort on missing element:** If `--grep` returns empty or `--press` exits `7`,
  stop immediately.
- **Poll for content:** Wait for a `h "` heading line to appear rather than
  using a fixed `sleep`.
- **Foreground the target tab:** Activate the target browser tab before running
  `--root webarea` so `axmd` reads the right document.
- **Web modals:** Many web modals do not expose `AXDialog`; locate buttons with
  `--grep` instead of `--root dialog`.
- **Chromium hydration:** `axmd` enables `AXManualAccessibility` automatically
  on first contact and skips the 150ms hydration sleep on subsequent calls.

## Release & CI pipeline

When modifying `axmd.swift` or the skill in the repository:

1. Keep root `axmd.swift` and `skills/axmd-computer-use/scripts/axmd.swift`
   identical (`make test` enforces `cmp -s` sync, `--help` smoke check, and
   `zsh -n` syntax validation).
2. Open a branch and PR; `.github/workflows/ci.yml` compiles the universal
   `arm64 + x86_64` binary via `lipo` and runs `make test` on `macos-14`.
3. Tagging `v*` (e.g. `git tag -a v0.1.1 -m "v0.1.1" && git push origin v0.1.1`)
   packages `axmd-<version>-macos-universal.tar.gz` (universal binary + `skills/`)
   and its `.sha256` digest into a GitHub Release automatically.
