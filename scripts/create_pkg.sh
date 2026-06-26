#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CodexVisual"
APP_IDENTIFIER="com.orangeshushu.CodexVisual"
BUILD_DIR="$ROOT_DIR/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
PKG_ROOT="$BUILD_DIR/pkg-root"
PKG_SCRIPTS="$BUILD_DIR/pkg-scripts"
COMPONENT_PKG="$BUILD_DIR/$APP_NAME-component.pkg"
PKG_PATH="$BUILD_DIR/$APP_NAME.pkg"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
PKG_SIGN_IDENTITY="${PKG_SIGN_IDENTITY:-${INSTALLER_SIGN_IDENTITY:-}}"

"$ROOT_DIR/scripts/build_app.sh" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"

/bin/rm -rf "$PKG_ROOT" "$PKG_SCRIPTS" "$COMPONENT_PKG" "$PKG_PATH"
/bin/mkdir -p "$PKG_ROOT" "$PKG_SCRIPTS"
STAGED_APP="$PKG_ROOT/$APP_NAME.app"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr "$APP_PATH" "$STAGED_APP"

/bin/cat > "$PKG_SCRIPTS/preinstall" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail

/usr/bin/pkill -x "CodexVisual" 2>/dev/null || true
/usr/bin/pkill -x "CodexQuotaBar" 2>/dev/null || true
/bin/rm -rf "/Applications/CodexQuotaBar.app"
/bin/rm -rf "/Applications/Codex Visual.app"
/bin/rm -rf "$HOME/Applications/CodexVisual.app" 2>/dev/null || true
/bin/rm -rf "$HOME/Applications/CodexQuotaBar.app" 2>/dev/null || true
/bin/rm -rf "$HOME/Applications/Codex Visual.app" 2>/dev/null || true
exit 0
SCRIPT

/bin/cat > "$PKG_SCRIPTS/postinstall" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail

/usr/bin/xattr -dr com.apple.quarantine "/Applications/CodexVisual.app" 2>/dev/null || true

CONSOLE_USER="$(/usr/bin/stat -f %Su /dev/console)"
if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" ]]; then
  USER_ID="$(/usr/bin/id -u "$CONSOLE_USER" 2>/dev/null || true)"
  if [[ -n "$USER_ID" ]]; then
    /bin/launchctl asuser "$USER_ID" /usr/bin/open -a "/Applications/CodexVisual.app" 2>/dev/null || true
  fi
fi

exit 0
SCRIPT

/bin/chmod +x "$PKG_SCRIPTS/preinstall" "$PKG_SCRIPTS/postinstall"
/usr/bin/xattr -cr "$STAGED_APP" "$PKG_SCRIPTS" 2>/dev/null || true
/usr/bin/find "$STAGED_APP" "$PKG_SCRIPTS" -name '._*' -delete

COPYFILE_DISABLE=1 /usr/bin/pkgbuild \
  --component "$STAGED_APP" \
  --identifier "$APP_IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/Applications" \
  --scripts "$PKG_SCRIPTS" \
  "$COMPONENT_PKG" >/dev/null

productbuild_args=(
  --package "$COMPONENT_PKG"
  --identifier "$APP_IDENTIFIER.installer"
  --version "$VERSION"
)

if [[ -n "$PKG_SIGN_IDENTITY" && "$PKG_SIGN_IDENTITY" != "-" ]]; then
  productbuild_args+=(--sign "$PKG_SIGN_IDENTITY")
fi

/usr/bin/productbuild "${productbuild_args[@]}" "$PKG_PATH" >/dev/null

if [[ -n "$PKG_SIGN_IDENTITY" && "$PKG_SIGN_IDENTITY" != "-" ]]; then
  /usr/sbin/pkgutil --check-signature "$PKG_PATH" >/dev/null
else
  echo "Created unsigned PKG. Set PKG_SIGN_IDENTITY='Developer ID Installer: ...' for public release builds." >&2
fi

echo "$PKG_PATH"
