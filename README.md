# webview-latency-spike

Standalone spike measuring **touch-drag latency of a web page rendered through gdcef
(CPU off-screen rendering → Godot texture) on Godot 4.4.1**, on a Windows touch panel.

**Question it answers:** is CPU-OSR latency acceptable for an air-hockey-style drag game
before committing to a gdcef multi-touch fork and integrating into the host application?

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

## Multi-touch

The stock gdcef v0.17.0 dll is single-pointer (mouse only). This spike also supports a
**forked dll** ([ClintonSarkar/gdcef](https://github.com/ClintonSarkar/gdcef), branch
`multitouch-v0.17`) that adds per-finger `set_touch_down/move/up/cancel` wrapping CEF's
`SendTouchEvent`. The spike auto-detects it at startup (`MULTITOUCH_API: true/false` in the
console) — with the fork, Input:Touch mode forwards each finger separately and the page
receives real multi-point `touchstart`/`touchmove`/`touchend` (up to 16 fingers, CEF limit).
dragtest.html gives each finger its own puck and reports `fingers N` in the HUD.

**Rebuild the dll** (Windows, VS2022 + Python + scons): clone the fork, checkout
`multitouch-v0.17`, `pip install -r requirements.txt`, run `python build.py` from a VS x64
dev prompt in `addons/gdcef/` (note: its post-build demo-symlink step needs admin and may
fail — harmless, the dll is already built at `<repo>/cef_artifacts/libgdcef.dll`). Then copy
**only `libgdcef.dll`** over `cef_artifacts/libgdcef.dll` here (stock kept as
`libgdcef.dll.stock`). For exported builds, also replace the `libgdcef.dll` sitting next to
the exported exe. Nothing else changes (same CEF 131, same artifacts).

**Automated check**: `bin\Godot_v4.4.1-stable_win64_console.exe --path . -- --touch-selftest`
injects two synthetic fingers and verifies the page counts them via `document.title`;
prints `TOUCH_SELFTEST_PASS`/`FAIL` and exits 0/1.

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

Background: this harness gates an integration where an existing multi-touch web game runs
as an interactive background layer inside a Godot app, beneath alpha overlays composited
on top. That layering rules out OS-native webview overlays (always top-most) — only
texture-rendering CEF embeds work, and on Godot 4.4.1 that means gdcef v0.17.0. Stock gdcef
has no touch API (mouse-only, single pointer), so multi-touch required forking it to map
Godot's per-finger `InputEventScreenTouch.index` → CEF `SendTouchEvent`. This spike first
gated the fork on latency (passed at 60 fps on hardware), then verified the fork end-to-end.
