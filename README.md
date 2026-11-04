<div align="center">

<img src="assets/hero.svg" alt="axmd — zero-screenshot macOS computer use" width="100%"/>

<br/>

[![CI & Release](https://github.com/elix1er/axmd/actions/workflows/ci.yml/badge.svg)](https://github.com/elix1er/axmd/actions/workflows/ci.yml)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square&logo=swift&logoColor=white)](axmd.swift)
[![Platform](https://img.shields.io/badge/platform-macOS_13%2B-000000?style=flat-square&logo=apple&logoColor=white)](axmd.swift)
[![IPC](https://img.shields.io/badge/AX_IPC-O(1)_batched-38bdf8?style=flat-square)](#architecture)
[![Agent Skill](https://img.shields.io/badge/SKILL.md-Codex_%7C_Claude_%7C_Antigravity-818cf8?style=flat-square)](skills/axmd-computer-use/SKILL.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-4ade80?style=flat-square)](LICENSE)

**Deterministic, token-minimal macOS computer use via the native Accessibility (`AXUIElement`) tree.**  
Single-file Swift binary · `O(1)` batched attribute IPC · index-free semantic `--diff` · headless `AXPress` dispatch.

[Architecture](#architecture) · [Benchmarks](#benchmarks) · [Quick Start](#quick-start) · [CLI Reference](#cli-reference) · [Agent Skill](#agent-skill)

</div>

---

## Why `axmd`?

Vision-based computer-use loops burn **1,500+ tokens per screenshot**, add 1–3 seconds of encoding latency per turn, and require coordinate guessing that breaks whenever a window moves. Raw `AXUIElement` dumps fix coordinate drift but emit **60+ KB of nested noise** per page (`AXGroup` wrappers, unlabeled icons, duplicate `AXStaticText` children, and 10+ Mach IPC round-trips per node).

`axmd` compresses the live macOS Accessibility tree into **1-line-per-element semantic refs** inspired by OpenAI Codex Computer Use (`@oai/sky`), directly addressable by integer index for zero-cursor headless interaction:

```text
12 b "Sign in"
13 l "Documentation" </docs/getting-started>
14 t "Search..." ="axmd" [foc]
15 c "Remember session" [on]
```

## Benchmarks

Measured on a live 1,587-node Safari web document on Apple Silicon (M-series):

| Approach | Payload Size | Est. Tokens / Turn | Latency | Cursor Hijack |
| :--- | :---: | :---: | :---: | :---: |
| **Raw AppleScript (`entire contents`)** | ~1,160 KB | ~290,000 tok | >12.0 s | Yes |
| **Unpruned AX Tree Walk** | 63.4 KB | ~15,850 tok | 1.74 s | No |
| **Vision Screenshot Loop (1080p)** | PNG / WebP | ~1,500–3,000 tok | ~1.50 s | Yes |
| **`axmd` Full Interactive Snapshot** | **10.9 KB** | **~2,720 tok** | **0.88 s** | **No (`AXPress`)** |
| **`axmd --diff` (Post-Action Delta)** | **~290 B** | **~73 tok** | **0.85 s** | **No (`AXPress`)** |
| **`axmd --grep` (Targeted Lookup)** | **~45 B** | **~12 tok** | **0.84 s** | **No (`AXPress`)** |

## Architecture

```mermaid
flowchart LR
    A["Agent / Shell Loop"] -->|"axmd App --diff / --press"| B["axmd CLI (Swift)"]
    B -->|"AXManualAccessibility = true"| C["macOS ApplicationServices"]
    C -->|"AXUIElementCopyMultipleAttributeValues\n(13 attrs in 1 Mach IPC call/node)"| D["Target App AX Tree"]
    D --> E["Pruning & Normalization\n• Drop unlabeled AXGroup/icons\n• Dedupe parent/child labels\n• Same-host relative URLs"]
    E --> F{"Mode"}
    F -->|"Snapshot / --grep"| G["Compact Indexed Lines\n<idx> <role> \"label\" =val [flags]"]
    F -->|"--diff"| H["Index-Agnostic Set Diff\nvs $TMPDIR/axmd-<pid>-<root>.txt"]
    F -->|"--press / --type"| I["Headless Dispatch\nAXPress / AXConfirm / AXValue"]
```

### Key Engineering Decisions

1. **Single-Roundtrip Batched IPC (`AXUIElementCopyMultipleAttributeValues`):** Fetching `AXRole`, `AXSubrole`, `AXTitle`, `AXDescription`, `AXValue`, `AXEnabled`, `AXFocused`, `AXChildren`, and `AXURL` individually requires 13 Mach IPC calls per node (~20,000 IPC calls per web page). `axmd` batches all 13 attributes into a single C-array IPC call per element, cutting traversal time in half.
2. **Chromium Lazy AX Hydration (`AXManualAccessibility`):** Chromium browsers do not build their internal DOM accessibility tree unless an assistive technology client registers. `axmd` asserts `AXManualAccessibility = kCFBooleanTrue` on the application PID before walking.
3. **Helper Process Disambiguation (`activationPolicy == .regular`):** Filters `NSWorkspace.shared.runningApplications` to regular GUI apps so Chromium/Electron renderer helpers never trigger ambiguous target errors.
4. **Shift-Resilient Semantic Diffs (`--diff`):** Stores the previous snapshot in `$TMPDIR/axmd-<pid>-<root>.txt` and strips leading element indices before computing set differences. Inserting a single banner node at the top of a page only emits `+ 1 line` rather than invalidating 400 shifted indices.

## Quick Start

### 1. Build or Install

```bash
make            # native build (swiftc -O axmd.swift -o axmd)
make universal  # fat binary (arm64 + x86_64) via lipo
make install    # installs to /usr/local/bin/axmd
```

Or download the prebuilt universal binary from [Releases](https://github.com/elix1er/axmd/releases).

> [!IMPORTANT]
> Grant **Accessibility** permission to your terminal or agent host in **System Settings › Privacy & Security › Accessibility**. No browser flags or AppleScript JS toggles are required.

### 2. Inspect & Act

```bash
# 1. Locate an element (returns index, 1-char role, label, state flags)
./axmd Safari --grep "Sign in"
# -> 12 b "Sign in"

# 2. Trigger headless click via AXPress (zero mouse movement or window focus theft)
./axmd Safari --press 12
# -> pressed 12: b "Sign in"

# 3. Inspect only the state delta since the last snapshot
./axmd Safari --diff
# -> + 4 t "Email address" [foc]
# -> (1+ 0- / 18)

# 4. Type into a text field by index
./axmd Safari --type 4 "user@example.com"
```

## CLI Reference

```text
usage: axmd <app> [--root s] [--window s] [--text] [--grep s] [--urls] [--tree] [--diff] [--press i] [--type i txt]
```

| Flag | Description |
| :--- | :--- |
| `<app>` | Application name (`"Google Chrome"`), bundle ID (`com.apple.Safari`), or PID |
| `--root <s>` | Scope walk to first descendant matching role/subrole (`dialog`, `webarea`, `tabgroup`, `toolbar`) |
| `--window <s>` | Match window by title substring (defaults to `AXFocusedWindow`) |
| `--grep <s>` | Filter output to lines matching case-insensitive substring (does not overwrite `--diff` cache) |
| `--diff` | Emit only `+` added and `-` removed elements compared to previous snapshot for `<pid>-<root>` |
| `--press <i>` | Dispatch `AXPress` (with `AXConfirm` fallback) on element `<idx>` |
| `--type <i> <s>` | Focus element `<idx>` and set its `AXValue` to `<s>` |
| `--text` | Include `AXStaticText` nodes (omitted by default to keep snapshots interactive-only) |
| `--urls` | Append `<href>` on links (automatically shortened to relative paths for same-host URLs) |
| `--tree` | Indent lines by AX tree depth |
| `--max <n>` | Hard cap on visited nodes (default: `3000`) |

### Role & Flag Legend

- **Roles:** `b` button · `l` link · `t` textfield/combobox · `c` checkbox/disclosure · `r` radio · `p` popup/menu button · `m` menuitem · `s` slider · `tab` tab · `h` heading · `x` static text · `dlg` dialog/sheet
- **State Flags:** `sel` selected · `foc` focused · `off` disabled · `open` expanded · `on` / `mixed` checked state

## Agent Skill

[`skills/axmd-computer-use/`](skills/axmd-computer-use/SKILL.md) packages `axmd` and [`loop.sh`](skills/axmd-computer-use/scripts/loop.sh) as a vendor-neutral `SKILL.md` for autonomous coding agents:

| Agent Runtime | Installation Path |
| :--- | :--- |
| **OpenAI Codex** | `cp -R skills/axmd-computer-use ~/.codex/skills/` |
| **Claude Code** | `cp -R skills/axmd-computer-use ~/.claude/skills/` |
| **Google Antigravity / Gemini** | `cp -R skills/axmd-computer-use .agents/skills/` |

## License

Released under the [MIT License](LICENSE).
