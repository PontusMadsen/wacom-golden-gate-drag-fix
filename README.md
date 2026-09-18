# Wacom pen/touch window-drag fix for macOS 26+

Older Wacom tablets (e.g. the **CTH-680 Intuos Pen & Touch**) whose newest
supported driver is the **6.3.x** line lose the ability to **drag windows by
their title bar** on recent macOS. The pen still tracks, clicks, draws, and
drags *files* — but grabbing a window's title bar to move it (including
dragging across Spaces / into Mission Control) does nothing. Touch tap-to-click
may also break.

Tested on **macOS "Golden Gate" (`sw_vers` reports 27.0, build 26A428)**; the
underlying WindowServer change likely affects macOS 26 (Tahoe) as well.

This is a small, reversible fix that restores native window dragging for the
pen **and** touch.

> ⚠️ **Read "What this changes / risks" before running.** This re-signs one
> Apple/Wacom-signed helper on your Mac and disables some of its code-signing
> protections. It's reversible (`uninstall.sh`), but understand it first.

---

## Who this is for

- A Wacom tablet supported only up to driver **6.3.x** (last release for many
  2013-era Intuos models: **6.3.46-2 / 6.3.46f2**).
- macOS **26 or newer** (Tahoe / Golden Gate).
- The pen tracks and clicks, but **cannot drag windows**.

If you're on the current 6.4.x driver line (newer tablets), this isn't your
problem — the 6.4.x driver emits events differently and doesn't have this bug.

## The root cause

Wacom's `com.wacom.IOManager` helper builds pointer events with
`CGEventCreate` + `CGEventSetType` — a *generic* event stamped with a mouse
type — instead of `CGEventCreateMouseEvent`. Regular apps accept those (so
clicks and in-app drags work), but macOS 26's **WindowServer title-bar drag
gesture recognizer only honours events built by `CGEventCreateMouseEvent`** and
silently ignores the generic ones. (It already posts via the modern
`CGEventPost` to the HID tap — so it is *not* an event-tap/pressure/API issue,
which is what most guesses assume.)

## How the fix works

A ~40-line dynamic library (`libwacomdragfix.dylib`) is injected into
`com.wacom.IOManager` via `DYLD_INSERT_LIBRARIES`. It interposes `CGEventPost`
and, for mouse button/drag events, **rebuilds them with
`CGEventCreateMouseEvent`** (carrying over tablet subtype, pressure/tilt, the
single/double click-count, and modifier flags) before posting. WindowServer
then accepts the drag. Everything else passes through untouched.

To let an unsigned dylib load into that helper, `install.sh` re-signs
`com.wacom.IOManager` **ad-hoc** (which removes its hardened-runtime and
App-Sandbox flags) and adds the `DYLD_INSERT_LIBRARIES` line to its launch
agent. Your original binary and launch agent are backed up first.

## What this changes / risks

- **Re-signs `com.wacom.IOManager` ad-hoc**, dropping its hardened runtime,
  library validation, and App Sandbox. Only that one helper (which already runs
  as your user) is affected. No SIP changes, no kexts, no other binaries.
- **You must re-grant Accessibility** to IOManager afterward (its code identity
  changed, so the old permission no longer matches). `install.sh` tells you how.
- **Fully reversible** with `uninstall.sh`, which restores the backed-up factory
  binary and launch agent.
- Reapply after any Wacom driver reinstall/update (it overwrites these files).
  For EOL tablets there are no more driver updates, so this is effectively
  one-time.

## Install

```bash
git clone <this repo> wacom-golden-gate-drag-fix
cd wacom-golden-gate-drag-fix
sudo ./install.sh
```

Then, as the installer instructs:

1. **System Settings → Privacy & Security → Accessibility**: remove any existing
   `com.wacom.IOManager` entry, click **+**, press **⌘⇧G**, paste
   `/Library/PrivilegedHelperTools/com.wacom.IOManager.app`, add it, toggle ON.
2. Test: pen click, **double-click**, and **drag a window** by its title bar. If
   touch tap-to-click is dead but the pen works, restart the touch driver once
   (also happens on reboot):
   ```bash
   sudo pkill -f WacomTouchDriver
   launchctl kickstart -k gui/$(id -u)/com.wacom.wacomtablet
   ```

Building from source needs Xcode Command Line Tools
(`xcode-select --install`, then accept the licence). If `clang` isn't
available, the installer falls back to the prebuilt universal
`dist/libwacomdragfix.dylib`.

## Uninstall

```bash
sudo ./uninstall.sh
```

## Credits

Diagnosed and built collaboratively; root-caused by disassembling
`com.wacom.IOManager` (`-[PostEvents PostIOHIDEvent:at:eventData:options:flags:]`)
and confirming the `CGEventCreateMouseEvent`-vs-generic-event discriminator with
controlled synthetic event tests.

## Licence

MIT. Provided as-is, no warranty. You are modifying signed system components at
your own risk.
