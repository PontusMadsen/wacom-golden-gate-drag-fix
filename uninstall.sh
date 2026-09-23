#!/bin/bash
# Revert to the factory Wacom driver. Run with: sudo ./uninstall.sh
set -euo pipefail

HELPERS="/Library/PrivilegedHelperTools"
AGENT="/Library/LaunchAgents/com.wacom.IOManager.plist"
DYLIB_DST="/Library/PrivilegedHelperTools/libwacomdragfix.dylib"
REPO="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$REPO/backup-$(hostname -s)"

[ "$(id -u)" = 0 ] || { echo "Please run with sudo: sudo ./uninstall.sh"; exit 1; }

if [ -d "$BACKUP/com.wacom.IOManager.app" ]; then
  IOMAPP="$HELPERS/com.wacom.IOManager.app"
  IOMBACKUP="$BACKUP/com.wacom.IOManager.app"
  IOMLABEL="com.wacom.IOManager"
elif [ -d "$BACKUP/Wacom_IOManager.app" ]; then
  IOMAPP="$HELPERS/Wacom_IOManager.app"
  IOMBACKUP="$BACKUP/Wacom_IOManager.app"
  IOMLABEL="Wacom_IOManager"
else
  echo "No backup found at $BACKUP — cannot revert."; exit 1
fi
CONSOLE_UID="$(stat -f%u /dev/console)"

echo "Restoring factory IOManager + launch agent from $BACKUP"
rm -rf "$IOMAPP"
cp -R "$IOMBACKUP" "$IOMAPP"; chown -R root:wheel "$IOMAPP"
cp "$BACKUP/com.wacom.IOManager.plist" "$AGENT"; chown root:wheel "$AGENT"; chmod 644 "$AGENT"
rm -f "$DYLIB_DST"

echo "Restarting IOManager + touch driver"
launchctl bootout "gui/$CONSOLE_UID/$IOMLABEL" 2>/dev/null || true
launchctl enable "gui/$CONSOLE_UID/$IOMLABEL" 2>/dev/null || true
launchctl bootstrap "gui/$CONSOLE_UID" "$AGENT" 2>/dev/null || true
pkill -f "\.Tablet/WacomTouchDriver\.app" 2>/dev/null || true
launchctl kickstart -k "gui/$CONSOLE_UID/com.wacom.wacomtablet" 2>/dev/null || true

echo "Reverted to factory Wacom driver. You may re-enable the original"
echo "com.wacom.IOManager entry under Privacy & Security > Accessibility if needed."
