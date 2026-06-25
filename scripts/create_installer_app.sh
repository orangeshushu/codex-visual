#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CodexVisual"
INSTALLER_APP="$ROOT_DIR/build/CodexVisual Installer.app"

"$ROOT_DIR/scripts/build_app.sh" >/dev/null

/bin/rm -rf "$INSTALLER_APP"
/bin/mkdir -p "$INSTALLER_APP/Contents/MacOS" "$INSTALLER_APP/Contents/Resources"
/usr/bin/ditto "$ROOT_DIR/build/$APP_NAME.app" "$INSTALLER_APP/Contents/Resources/$APP_NAME.app"
/bin/cp "$ROOT_DIR/scripts/install.sh" "$INSTALLER_APP/Contents/Resources/install.sh"
/bin/cp "$ROOT_DIR/scripts/uninstall.sh" "$INSTALLER_APP/Contents/Resources/uninstall.sh"
/bin/chmod +x "$INSTALLER_APP/Contents/Resources/install.sh" "$INSTALLER_APP/Contents/Resources/uninstall.sh"

/bin/cat > "$INSTALLER_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>Installer</string>
    <key>CFBundleIdentifier</key>
    <string>local.codex-visual.installer</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CodexVisual Installer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

/bin/cat > "$INSTALLER_APP/Contents/MacOS/Installer" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

RESOURCE_DIR="$(cd "$(dirname "$0")/../Resources" && pwd)"

CHOICE="$(/usr/bin/osascript <<'APPLESCRIPT'
button returned of (display dialog "CodexVisual 菜单栏额度显示工具" buttons {"取消", "卸载", "安装"} default button "安装" cancel button "取消" with title "CodexVisual Installer")
APPLESCRIPT
)"

case "$CHOICE" in
  "安装")
    OUTPUT="$("$RESOURCE_DIR/install.sh" 2>&1)"
    /usr/bin/osascript -e 'display dialog "安装完成。菜单栏中会显示 Codex 额度；点击可查看刷新时间。" buttons {"好"} default button "好" with title "CodexVisual Installer"'
    ;;
  "卸载")
    OUTPUT="$("$RESOURCE_DIR/uninstall.sh" 2>&1)"
    /usr/bin/osascript -e 'display dialog "卸载完成。" buttons {"好"} default button "好" with title "CodexVisual Installer"'
    ;;
esac
SCRIPT

/bin/chmod +x "$INSTALLER_APP/Contents/MacOS/Installer"
/usr/bin/codesign --force --sign - "$INSTALLER_APP" >/dev/null

echo "$INSTALLER_APP"
