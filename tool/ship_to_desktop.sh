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

echo "==> verifying what landed"
codesign --verify --deep --strict "$DEST"
dart tool/verify_litert_app_bundle.dart "$DEST"

echo
echo "Lulo.app is on the Desktop. Double-click to run."
