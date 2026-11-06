#!/bin/bash
# Build a self-contained universal macOS installer. No third-party runtime needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${VERSION:-0.1.1}"
case "$VERSION" in *[!0-9.]*|'') echo 'VERSION must contain digits and dots.' >&2; exit 1;; esac
OUTPUT="$ROOT/Outputs/Releases/$VERSION"
if [ -e "$OUTPUT" ]; then
  echo "Release directory already exists: $OUTPUT. Use a new VERSION; releases are not overwritten." >&2
  exit 1
fi
if [ -n "${NOTARY_PROFILE:-}" ] && { [ -z "${APP_SIGN_IDENTITY:-}" ] || [ -z "${INSTALLER_SIGN_IDENTITY:-}" ]; }; then
  echo 'Notarization requires both Developer ID Application and Installer identities.' >&2
  exit 1
fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/timestamper-release.XXXXXX")"
echo "Build workspace: $WORK"
xcodebuild -project timestamper.xcodeproj -scheme 'TimeStamper App' \
  -configuration Release -derivedDataPath "$WORK/build" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" build > "$WORK/build.log" 2>&1 || {
    cat "$WORK/build.log"; exit 1;
  }
APP="$WORK/root/Applications/TimeStamper.app"
mkdir -p "$WORK/root/Applications"
ditto "$WORK/build/Build/Products/Release/TimeStamper.app" "$APP"
if [ -n "${APP_SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
ARCHITECTURES="$(lipo -archs "$APP/Contents/MacOS/TimeStamper")"
for EXPECTED_ARCH in arm64 x86_64; do
  case " $ARCHITECTURES " in
    *" $EXPECTED_ARCH "*) ;;
    *) echo "Missing architecture: $EXPECTED_ARCH" >&2; exit 1;;
  esac
done
pkgbuild --analyze --root "$WORK/root" "$WORK/components.plist"
/usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$WORK/components.plist"
# Keep /Applications as the destination even if a development build exists elsewhere.
set --
LABEL=unsigned
if [ -n "${INSTALLER_SIGN_IDENTITY:-}" ]; then
  set -- --sign "$INSTALLER_SIGN_IDENTITY"
  LABEL=signed
fi
PKG="TimeStamper-$VERSION-universal-$LABEL.pkg"
pkgbuild --root "$WORK/root" --component-plist "$WORK/components.plist" \
  --install-location / --identifier com.timestamper.desktop.installer \
  --version "$VERSION" "$@" "$WORK/$PKG"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$WORK/$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$WORK/$PKG"
  xcrun stapler validate "$WORK/$PKG"
  spctl --assess --type install --verbose=2 "$WORK/$PKG"
fi
mkdir -p "$OUTPUT"
cp "$WORK/$PKG" "$OUTPUT/$PKG"
ditto "$APP" "$OUTPUT/TimeStamper.app"
if [ -z "${NOTARY_PROFILE:-}" ]; then
  printf '%s\n' 'Development preview: this installer has not been notarized by Apple.' \
    'macOS Gatekeeper may block downloaded copies. Do not disable system security.' \
    'Build from source or use a later Developer ID-signed and notarized release for distribution.' > "$OUTPUT/INSTALLATION-NOTE.txt"
fi
(cd "$OUTPUT" && shasum -a 256 "$PKG" > SHA256SUMS.txt)
echo "Installer: $OUTPUT/$PKG"
echo 'The installer places TimeStamper.app in /Applications. No source checkout or Swift installation is needed to run it.'
