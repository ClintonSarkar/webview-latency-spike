# webview-latency-spike

Standalone spike measuring **touch-drag latency of a web page rendered through gdcef
(CPU off-screen rendering → Godot texture) on Godot 4.4.1**, on a Windows touch panel.

**Question it answers:** is CPU-OSR latency acceptable for an air-hockey-style drag game
before we commit to a gdcef multi-touch fork and signager integration?

This is spike-only. No signage integration here. Single pointer only (latency, not multitouch).

## One-time setup

```powershell
./fetch-artifacts.ps1
```

Downloads (never committed): `cef_artifacts/` (gdcef v0.17.0 Windows x64, built vs Godot 4.3 —
loads on 4.4.1 via GDExtension forward-compat) and `bin/` (pinned Godot 4.4.1 editor).

> Do NOT open this project with any other Godot version — the PATH `godot` on the dev box
> is 4.6 and will rewrite scenes and invalidate the 4.4.1 premise.

## Run

```powershell
bin\Godot_v4.4.1-stable_win64.exe --path .
```

First run imports and boots into the bundled drag-test page. F11 for fullscreen on the panel.

## Controls

| Control | Action |
|---|---|
| URL bar + Go / Enter | load any website |
| `Drag Test` button | load the bundled instrumented drag page |
| `FR:30/60` button / F2 | toggle browser `windowless_frame_rate` (recreates browser) |
| `Input:Touch/Emulated` button / F1 | touch forwarding mode (see below) |
| F3 | toggle the Godot crosshair |
| F11 / Esc | fullscreen / quit |

**Input modes** — `Touch`: forwards `InputEventScreenTouch/Drag` directly to the browser
(production-representative). `Emulated`: relies on Godot's `emulate_mouse_from_touch`
synthesized mouse events (zero-code baseline). Test both; they can differ in latency.

## How to read the result

The **green/red ring (crosshair)** is drawn by Godot at the position it saw your pointer this
frame (~1 frame behind your finger). The **puck** is drawn by the web page with zero easing.
During a fast drag, the visible gap between ring and puck **is** the webview pipeline's added
latency. Screen-record at 60fps and step frames to count it.

The page HUD also shows: page fps (CEF paint rate), move events/sec reaching the page, and
event→frame ms inside the page.

**Baseline:** open `dragtest.html` in Edge fullscreen on the same panel (it handles native
touch). That is what "no webview pipeline" feels like — compare against it.

## Exporting for the panel

The Windows Desktop preset packs `dragtest.html` into the PCK (`include_filter="*.html"`),
so the Drag Test button works in exported builds — `main.gd` reads it from `res://` and
copies it to `user://` at startup (CEF needs a real file path, not a pack path).

1. Export with the pinned editor (needs 4.4.1 export templates installed once):
   `bin\Godot_v4.4.1-stable_win64_console.exe --path . --headless --export-release "Windows Desktop" <out>\webview-latency-spike.exe`
2. **Copy the whole `cef_artifacts/` folder next to the exported exe** — CEF's runtime
   (`gdCefRenderProcess.exe`, .pak files, locales) is not packed and is resolved beside
   the binary at runtime (same layout as gdcef's own shipped export example).
3. **Target machine needs the MSVC runtime** — libgdcef.dll depends on MSVCP140.dll /
   VCRUNTIME140.dll / VCRUNTIME140_1.dll. Install once: https://aka.ms/vs/17/release/vc_redist.x64.exe
   (or copy those three x64 DLLs next to the exe). Without it the DLL fails with
   `Error 126`, GDCef becomes a placeholder, and the app shows a grey page.

The drag test loads automatically at startup (packed page → copied to `user://` → `file://`
URL). Never type `res://` in the URL bar — CEF cannot read Godot pack paths; the Drag Test
button does the copy + file:// dance for you.

## Test matrix

Run each on the physical touch panel, fast drags and flicks, not slow ones:

| # | frame_rate | input mode | page |
|---|---|---|---|
| 1 | 30 | Touch | Drag Test |
| 2 | 60 | Touch | Drag Test |
| 3 | 60 | Emulated | Drag Test |
| 4 | 60 | Touch | a real website (URL bar) |
| baseline | — | native | dragtest.html in Edge fullscreen |

Also note CPU % (Task Manager: this app + `gdCefRenderProcess`) during test 2.

## Verdict criteria

| Fast-drag feel vs Edge baseline | Meaning | Next step |
|---|---|---|
| Puck tracks tightly, gap ≈ baseline | CPU-OSR latency acceptable | build the multi-touch fork (SendTouchEvent) |
| Puck visibly trails the finger | OSR lag is architectural | reconsider webview for this game (GPU-CEF/godot-cef on 4.6 + Vulkan, or no webview) |

## Context

Decision history lives with the signager webview-background investigation (2026-06/07):
gdcef is the only texture-rendering webview family on 4.4.1; it has no touch API (mouse-only,
single pointer), so multi-touch requires forking it to map Godot's per-finger
`InputEventScreenTouch.index` → CEF `SendTouchEvent`. This spike gates that fork on latency.
