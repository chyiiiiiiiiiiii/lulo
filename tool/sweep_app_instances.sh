#!/bin/sh
# Close app windows the tests opened and did not.
#
# Steps 14, 14a and 17 of `tool/verify.dart` launch real macOS windows. An
# instance that outlives its test stays in the Dock, and the next gate run
# hangs on it — the xcodebuild test host refuses to connect while another
# process holds the same bundle ID.
#
# Matches the **build directory**, not the process name. A Lulo installed to
# /Applications is the user's own resident agent and is none of this
# script's business; so are the sidecars, which live outside this repository
# and take voice and the batch recogniser down with them.
#
# Prints a Claude Code hook `systemMessage` when it actually closed
# something, and stays silent when there was nothing to close. Always exits
# 0: a sweep that finds nothing is the normal case, not a failure.
set -u

PATTERN="Products/(Debug|Profile)/Lulo.app"

count=$(pgrep -f "$PATTERN" 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -gt 0 ]; then
  pkill -f "$PATTERN" 2>/dev/null
  printf '{"systemMessage": "Closed %s leftover Lulo window(s) from the build directory."}\n' "$count"
fi
exit 0
