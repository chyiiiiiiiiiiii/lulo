#!/bin/sh
# Build the shipping app and put it on the Desktop, ready to double-click.
#
# Release rather than Profile. The gate builds `--profile`, which signs with
# DebugProfile.entitlements — so the only build anybody ever looks at is not
# the one that ships. This runs `verify_release_entitlements.dart` against
# the file a released app is really signed with, then the LiteRT bundle gate
# against the copy that actually lands on the Desktop, because `ditto` is
# where a signature would break if it were going to.
#
# The bundle ID is unchanged, so the copy on the Desktop opens the same
# container as every other build: the installed models, the conversation
# history and the profile are all still there. Moving the app does not move
# its data.
#
# Deliberately not part of `verify.dart`. The gate is what says the code is
# correct; this is a delivery, and it takes several minutes of Release
# compilation that a checkpoint commit has no reason to pay for.
set -eu

cd "$(dirname "$0")/.."
ROOT=$(pwd)
BUNDLE="$ROOT/apps/local_agent_macos/build/macos/Build/Products/Release/Lulo.app"
DEST="$HOME/Desktop/Lulo.app"

echo "==> building Release"
(cd apps/local_agent_macos && flutter build macos --release)

echo "==> release entitlements"
(cd apps/local_agent_macos && dart tool/verify_release_entitlements.dart)

echo "==> copying to the Desktop"
# ditto rather than cp: it preserves the extended attributes and the code
# signature, and replaces the destination wholesale rather than merging into
# a stale bundle left by an older build.
rm -rf "$DEST"
ditto "$BUNDLE" "$DEST"

# Re-signed with a real identity when the machine has one, and this is not
# cosmetic: the project signs ad-hoc (`CODE_SIGN_IDENTITY = "-"`, correct
# for CI, which has no certificates), and TCC keys an ad-hoc app's consent
# to its **cdhash**. Every rebuild is a new cdhash, so every ship silently
# revoked the Screen Recording grant the user had already given — System
# Settings kept showing the switch on, because the entry it belongs to is
# the previous binary. A development certificate carries a stable team
# identifier, which is an identity TCC can hold a grant against across
# rebuilds. Falls back to the ad-hoc bundle with a warning rather than
# failing: an app that runs is worth more than a permission that persists.
# By SHA-1 rather than by name: two certificates on this machine share the
# name "Apple Development: …", and codesign refuses an ambiguous match.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Apple Development" | head -1 | awk '{print $2}')
if [ -n "$IDENTITY" ]; then
  echo "==> re-signing as $IDENTITY"
  # Nested code first, outermost last: signing the bundle seals what is
  # inside it, so a dylib signed afterwards invalidates the seal above it.
  find "$DEST/Contents/Frameworks" -name "*.dylib" -o -name "*.framework" \
    -maxdepth 1 2>/dev/null | while read -r nested; do
    codesign --force --sign "$IDENTITY" --timestamp=none "$nested" \
      >/dev/null 2>&1 || true
  done
  # No hardened runtime: nothing here is notarized, and it would only add a
  # way for the vendored LiteRT dylib's loading to break.
  codesign --force --deep --sign "$IDENTITY" --timestamp=none \
    --entitlements "$ROOT/apps/local_agent_macos/macos/Runner/Release.entitlements" \
    "$DEST"
else
  echo "==> no development certificate; leaving the ad-hoc signature"
  echo "    (macOS will forget Screen Recording consent on every ship)"
fi

echo "==> verifying what landed"
codesign --verify --deep --strict "$DEST"
dart tool/verify_litert_app_bundle.dart "$DEST"

echo
echo "Lulo.app is on the Desktop. Double-click to run."
