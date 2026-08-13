#!/bin/bash
# Re-sign Sparkle's nested helpers, then the app that contains them.
#
#   scripts/sign_sparkle.sh <path/to/Haze.app> "<signing identity>"
#
# Xcode signs the targets it builds, but not code *inside* a binary package
# dependency. Sparkle ships a helper app, a bare Autoupdate binary and two XPC
# services that keep the ad-hoc signature they were published with. Two things
# break if they stay that way:
#
#   - Apple rejects the whole archive at notarization ("not signed with a valid
#     Developer ID certificate", "does not include a secure timestamp");
#   - Sparkle refuses to launch its own installer when Autoupdate is not signed
#     with the same identity as the app, which the user sees as the useless
#     "An error occurred while launching the installer."
#
# The second one is why this lives in its own script rather than inside the
# release: `make install` needs it just as much, and an invariant enforced in
# only one of two places is the bug it is meant to prevent.
set -euo pipefail

APP="${1:-}"
IDENTITY="${2:-Developer ID Application}"

[ -n "$APP" ] || { echo "Usage: $0 <path/to/App.app> [identity]" >&2; exit 1; }
[ -d "$APP" ] || { echo "No app bundle at $APP" >&2; exit 1; }

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ ! -d "$SPARKLE" ]; then
    echo "No Sparkle.framework in $APP — nothing to do."
    exit 0
fi

sign() {
    codesign --force --options runtime --timestamp \
        --preserve-metadata=entitlements --sign "$IDENTITY" "$1" >/dev/null 2>&1 \
        || { echo "Could not re-sign $1" >&2; exit 1; }
    echo "  signed $(basename "$1")"
}

# Deepest first: the helpers, then the framework version that seals them, then
# the app that seals the framework.
for version in "$SPARKLE"/Versions/*/; do
    version="${version%/}"
    [ "$(basename "$version")" != "Current" ] || continue   # symlink to the real one
    for helper in "$version"/XPCServices/*.xpc "$version"/Updater.app "$version"/Autoupdate; do
        [ -e "$helper" ] && sign "$helper"
    done
    sign "$version"
done

# The app carries no entitlements of its own — do not preserve any, so the debug
# `get-task-allow` that Xcode injects can never survive into a release.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP" >/dev/null 2>&1 \
    || { echo "Could not re-sign $APP" >&2; exit 1; }
echo "  signed $(basename "$APP")"

codesign --verify --deep --strict "$APP" || { echo "Verification failed" >&2; exit 1; }
