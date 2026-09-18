#!/bin/bash
# Wacom pen/touch window-drag fix for macOS 26+ ("Tahoe"/"Golden Gate").
# Restores native window dragging with the pen/touch for older Wacom tablets
# whose last driver is 6.3.x (e.g. CTH-680 Intuos Pen & Touch on 6.3.46-2).
# See README.md for what this changes and the risks. Run with: sudo ./install.sh
set -euo pipefail

IOMAPP="/Library/PrivilegedHelperTools/com.wacom.IOManager.app"
AGENT="/Library/LaunchAgents/com.wacom.IOManager.plist"
DYLIB_DST="/Library/PrivilegedHelperTools/libwacomdragfix.dylib"
REPO="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$REPO/backup-$(hostname -s)"

[ "$(id -u)" = 0 ] || { echo "Please run with sudo: sudo ./install.sh"; exit 1; }
[ -d "$IOMAPP" ] || { echo "Wacom IOManager not found at $IOMAPP."; echo "Install the Wacom 6.3.x driver first."; exit 1; }
CONSOLE_UID="$(stat -f%u /dev/console)"

echo "[1/5] Backing up factory IOManager + launch agent -> $BACKUP"
mkdir -p "$BACKUP"
[ -e "$BACKUP/com.wacom.IOManager.app" ]  || cp -R "$IOMAPP" "$BACKUP/com.wacom.IOManager.app"
[ -e "$BACKUP/com.wacom.IOManager.plist" ] || cp "$AGENT" "$BACKUP/com.wacom.IOManager.plist"

echo "[2/5] Installing the interpose dylib -> $DYLIB_DST"
if command -v clang >/dev/null 2>&1 && clang -v >/dev/null 2>&1; then
  echo "      (building from source)"
  clang -arch arm64 -arch x86_64 -dynamiclib -framework ApplicationServices \
        -o "$DYLIB_DST" "$REPO/src/wacomdragfix.c"
else
  echo "      (clang unavailable — using prebuilt dist/libwacomdragfix.dylib)"
  cp "$REPO/dist/libwacomdragfix.dylib" "$DYLIB_DST"
fi
codesign --force --sign - "$DYLIB_DST"
chown root:wheel "$DYLIB_DST"; chmod 644 "$DYLIB_DST"

echo "[3/5] Re-signing IOManager ad-hoc (drops hardened runtime + sandbox so the dylib can load)"
codesign --remove-signature "$IOMAPP" 2>/dev/null || true
codesign --force --sign - "$IOMAPP/Contents/MacOS/com.wacom.IOManager"
codesign --force --sign - "$IOMAPP"

echo "[4/5] Adding DYLD_INSERT_LIBRARIES to the launch agent"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables dict" "$AGENT" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:DYLD_INSERT_LIBRARIES string $DYLIB_DST" "$AGENT" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:DYLD_INSERT_LIBRARIES $DYLIB_DST" "$AGENT"

echo "[5/5] Restarting IOManager + touch driver"
launchctl bootout "gui/$CONSOLE_UID/com.wacom.IOManager" 2>/dev/null || true
sleep 1
launchctl enable "gui/$CONSOLE_UID/com.wacom.IOManager" 2>/dev/null || true
launchctl bootstrap "gui/$CONSOLE_UID" "$AGENT" 2>/dev/null || true
sleep 1
launchctl kickstart "gui/$CONSOLE_UID/com.wacom.IOManager" 2>/dev/null || true
pkill -f "\.Tablet/WacomTouchDriver\.app" 2>/dev/null || true
launchctl kickstart -k "gui/$CONSOLE_UID/com.wacom.wacomtablet" 2>/dev/null || true

cat <<EOF

Done. TWO MANUAL STEPS REMAIN — the fix won't work until you do #1:

  1. Re-grant Accessibility (re-signing changed IOManager's identity):
     System Settings > Privacy & Security > Accessibility.
     REMOVE any existing "com.wacom.IOManager" entry, then click "+",
     press Cmd-Shift-G, paste:
         $IOMAPP
     add it, and make sure it is toggled ON.

  2. If touch tap-to-click doesn't work but the pen does, restart the touch
     driver once (also happens automatically on reboot):
         sudo pkill -f WacomTouchDriver
         launchctl kickstart -k gui/$CONSOLE_UID/com.wacom.wacomtablet

To undo everything: sudo ./uninstall.sh
EOF
