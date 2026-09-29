#!/bin/bash
# Builds Nudge.app: the Rust guide engine, the Swift app and its icon, then signs the bundle.
#
# Settings come from the environment or a .env file at the repository root (see .env.example):
#   NUDGE_SIGN_IDENTITY  signing identity (default "-", ad-hoc)
#   NUDGE_APP_PATH       where to put the app (default build/Nudge.app)
#   NUDGE_CONFIGURATION  release (default) or debug
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then set -a; source "$ROOT/.env"; set +a; fi

CONFIG="${NUDGE_CONFIGURATION:-release}"
IDENTITY="${NUDGE_SIGN_IDENTITY:--}"
APP="${NUDGE_APP_PATH:-build/Nudge.app}"
[[ "$APP" = /* ]] || APP="$ROOT/$APP"
BUILD="${NUDGE_BUILD_DIR:-$ROOT/.build}"
export CLANG_MODULE_CACHE_PATH="$BUILD/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD/swift-cache"

cargo_flags=(--manifest-path "$ROOT/engine/Cargo.toml" --locked)
[[ "$CONFIG" == release ]] && cargo_flags+=(--release)
echo "==> Building the guide engine ($CONFIG)"
cargo build "${cargo_flags[@]}"
echo "==> Building the app ($CONFIG)"
swift build --package-path "$ROOT" --scratch-path "$BUILD/swift" -c "$CONFIG" --product Nudge

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/swift/$CONFIG/Nudge" "$APP/Contents/MacOS/Nudge"
cp "$ROOT/engine/target/$CONFIG/nudge-engine" "$APP/Contents/MacOS/nudge-engine"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# The app icon is drawn from the character by the app itself.
rm -rf "$BUILD/AppIcon.iconset"
if "$BUILD/swift/$CONFIG/Nudge" --export-icon "$BUILD/AppIcon.iconset" >/dev/null 2>&1 \
    && iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"; then :
else echo "warning: skipped the app icon"; fi

# A stable identity keeps macOS privacy permissions across rebuilds; ad-hoc builds need them granted again.
echo "==> Signing with ${IDENTITY/#-/an ad-hoc signature}"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP/Contents/MacOS/nudge-engine"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
echo "Built $APP"
