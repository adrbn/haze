#!/bin/bash
# Cut a Haze release from this Mac, in one command.
#
# The GitHub workflow does the same thing, but a CI runner has no certificate —
# which is the only reason the workflow needs a .p12 exported, base64-encoded and
# split across five repo secrets. Your certificate is already in your keychain,
# so releasing from here skips all of that. What's left is one Apple API key,
# stored once by `notarytool` (see README).
#
#   ./scripts/release.sh v0.1.4
#
# Everything is checked before anything is published: the tree has to be clean,
# the tag unused, the certificate present, the notary profile stored, and the
# Sparkle key readable. The GitHub release is the very last step, so a failure
# anywhere leaves nothing half-published.
set -euo pipefail

TAG="${1:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-haze}"
SIGN_ID="${SIGN_ID:-Developer ID Application}"
SPARKLE_KEY=".secrets/sparkle_ed_private_key"
REPO_SLUG="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

die() { printf '\n\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

# `cmd | grep -q needle` is a trap here: grep exits at the first match, cmd then
# dies of SIGPIPE (141), and `set -o pipefail` reports the whole pipeline as
# failed — precisely when the match SUCCEEDED. Capture first, match after.
contains() { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

[ -n "$TAG" ] || die "Usage: ./scripts/release.sh vX.Y.Z"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Tag must look like v0.1.1 (got '$TAG')"

# ---------------------------------------------------------------- preflight
step "Checking everything is in place"

[ -z "$(git status --porcelain)" ] || die "Working tree is dirty — commit or stash first."
[ "$(git branch --show-current)" = "main" ] || die "Release from main (you are on $(git branch --show-current))."
git fetch --quiet --tags
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "Tag $TAG already exists."
[ "$(git rev-parse HEAD)" = "$(git rev-parse @{u})" ] || die "Local main differs from origin — push or pull first."

IDENTITIES="$(security find-identity -v -p codesigning || true)"
TEAM_ID="$(printf '%s\n' "$IDENTITIES" | grep "$SIGN_ID" | sed -n 's/.*(\([A-Z0-9]\{10\}\))".*/\1/p' | sed -n '1p')"
[ -n "$TEAM_ID" ] || die "No '$SIGN_ID' certificate in your keychain."

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "No notary profile '$NOTARY_PROFILE'. Run: xcrun notarytool store-credentials $NOTARY_PROFILE --key AuthKey_XXX.p8 --key-id KEYID --issuer ISSUER"

[ -f "$SPARKLE_KEY" ] || die "Missing $SPARKLE_KEY — without it, installed copies reject the update."

SHORT="${TAG#v}"
BUILD="$(git rev-list --count HEAD)"
echo "  $TAG → version $SHORT, build $BUILD, team $TEAM_ID"

OUT="$(mktemp -d)/haze-release"; mkdir -p "$OUT"
APP="build/Build/Products/Release/Haze.app"

# ---------------------------------------------------------------- build
step "Building a signed Release"
rm -rf build
xcodebuild -project Haze.xcodeproj -scheme Haze -configuration Release -derivedDataPath build \
  MARKETING_VERSION="$SHORT" CURRENT_PROJECT_VERSION="$BUILD" \
  HAZE_CODE_SIGN_IDENTITY="$SIGN_ID" HAZE_DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build > "$OUT/build.log" 2>&1 || { tail -30 "$OUT/build.log"; die "Build failed — full log: $OUT/build.log"; }

# Xcode signs the targets it builds, but not the code *inside* a binary package
# dependency: Sparkle ships a helper app, a bare Autoupdate binary and two XPC
# services that stay ad-hoc, and Apple rejects the whole archive for them
# ("not signed with a valid Developer ID certificate", "no secure timestamp").
# Re-sign them deepest-first, preserving their own entitlements, then the
# framework, then the app — whose seal covers everything below it.
step "Re-signing Sparkle's nested helpers"
harden() {
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
    --sign "$SIGN_ID" "$1" >/dev/null 2>&1 || die "Could not re-sign $1"
  echo "  signed $(basename "$1")"
}
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
[ -d "$SPARKLE" ] || die "Sparkle.framework missing from the build."
for version in "$SPARKLE"/Versions/*/; do
  version="${version%/}"
  [ "$(basename "$version")" != "Current" ] || continue    # symlink to the real one
  for helper in "$version"/XPCServices/*.xpc "$version"/Updater.app "$version"/Autoupdate; do
    [ -e "$helper" ] && harden "$helper"
  done
  harden "$version"
done
# The app carries no entitlements of its own — do not preserve, so the debug
# `get-task-allow` can never sneak back in.
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP" >/dev/null 2>&1 \
  || die "Could not re-sign the app."

codesign --verify --deep --strict "$APP" || die "The build is not properly signed."
ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
if contains "get-task-allow" "$ENTITLEMENTS"; then
  die "The app still requests get-task-allow — Apple rejects that in a release."
fi
SIGN_INFO="$(codesign -dv --verbose=2 "$APP" 2>&1 || true)"
contains "Authority=Developer ID Application" "$SIGN_INFO" \
  || die "The build is not Developer ID-signed — an ad-hoc release can never auto-update."

# ---------------------------------------------------------------- notarize
step "Notarizing (Apple usually answers in 1-5 min)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/notarize.zip"
# `notarytool submit --wait` exits 0 as long as it got an answer — including
# "Invalid". Read the verdict, not the exit code, or a rejected build sails on
# to stapling and fails there with an unrelated-looking error.
NOTARY_OUT="$(xcrun notarytool submit "$OUT/notarize.zip" \
  --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 || true)"
printf '%s\n' "$NOTARY_OUT"
SUBMISSION_ID="$(printf '%s\n' "$NOTARY_OUT" | sed -n 's/^ *id: \([0-9a-f-]*\)$/\1/p' | sed -n '1p')"
if ! contains "status: Accepted" "$NOTARY_OUT"; then
  printf '\n\033[1mApple rejected it. Reasons:\033[0m\n'
  [ -n "$SUBMISSION_ID" ] && xcrun notarytool log "$SUBMISSION_ID" \
    --keychain-profile "$NOTARY_PROFILE" 2>&1 || true
  die "Notarization failed — nothing was published."
fi

xcrun stapler staple "$APP" || die "Stapling failed."
# spctl exits non-zero when it rejects, so read its verdict rather than its status.
GATEKEEPER="$(spctl --assess --type execute --verbose=2 "$APP" 2>&1 || true)"
contains "accepted" "$GATEKEEPER" \
  || die "Gatekeeper still rejects the app after notarization: $GATEKEEPER"
echo "  Gatekeeper: accepted"

# ---------------------------------------------------------------- package
step "Packaging the DMG and the Sparkle archive"
STAGE="$OUT/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Haze" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Haze.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/Haze.zip"

# Changelog: commit subjects since the previous tag.
PREV="$(git describe --tags --abbrev=0 2>/dev/null || true)"
git log --no-merges --pretty='%s' ${PREV:+"$PREV"..}HEAD > "$OUT/notes.txt"

# Sparkle's signing tool ships as a package artifact. Take it from the build we
# just made — Xcode's shared DerivedData is a cache that tools like CleanMyMac
# wipe, and the appcast is unsignable without it.
SIGN_UPDATE="build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[ -x "$SIGN_UPDATE" ] || die "sign_update missing from the build at $SIGN_UPDATE"

python3 scripts/make_appcast.py \
  --sign-update "$SIGN_UPDATE" --key-file "$SPARKLE_KEY" \
  --zip "$OUT/Haze.zip" --short "$SHORT" --build "$BUILD" \
  --url "https://github.com/$REPO_SLUG/releases/download/$TAG/Haze.zip" \
  --pubdate "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')" \
  --notes-file "$OUT/notes.txt" --out "$OUT/appcast.xml"

# ---------------------------------------------------------------- publish
step "Publishing $TAG to $REPO_SLUG"
printf '\nAbout to tag %s and publish a public release. Continue? [y/N] ' "$TAG"
read -r reply
[ "$reply" = "y" ] || die "Cancelled — nothing was published."

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" \
  --title "Haze $SHORT" \
  --notes-file "$OUT/notes.txt" \
  --generate-notes \
  "$OUT/Haze.dmg" "$OUT/Haze.zip" "$OUT/appcast.xml"

printf '\n\033[32m✓ Released %s\033[0m — signed, notarized, stapled, appcast published.\n' "$TAG"
echo "  https://github.com/$REPO_SLUG/releases/tag/$TAG"
echo
echo "Note: everyone on an ad-hoc build (every release up to v0.1.3) will NOT get"
echo "this update automatically — they have to download the DMG once by hand."
