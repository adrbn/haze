#!/bin/bash
# Cut a Haze release from this Mac, in one command.
#
# The GitHub workflow does the same thing, but a CI runner has no certificate —
# which is the only reason the workflow needs a .p12 exported, base64-encoded and
# split across five repo secrets. Your certificate is already in your keychain,
# so releasing from here skips all of that. What's left is one Apple API key,
# stored once by `notarytool` (see README).
#
#   ./scripts/release.sh v0.1.1
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

[ -n "$TAG" ] || die "Usage: ./scripts/release.sh vX.Y.Z"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Tag must look like v0.1.1 (got '$TAG')"

# ---------------------------------------------------------------- preflight
step "Checking everything is in place"

[ -z "$(git status --porcelain)" ] || die "Working tree is dirty — commit or stash first."
[ "$(git branch --show-current)" = "main" ] || die "Release from main (you are on $(git branch --show-current))."
git fetch --quiet --tags
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "Tag $TAG already exists."
[ "$(git rev-parse HEAD)" = "$(git rev-parse @{u})" ] || die "Local main differs from origin — push or pull first."

TEAM_ID="$(security find-identity -v -p codesigning | grep -m1 "$SIGN_ID" | sed -n 's/.*(\([A-Z0-9]\{10\}\))".*/\1/p')"
[ -n "$TEAM_ID" ] || die "No '$SIGN_ID' certificate in your keychain."

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "No notary profile '$NOTARY_PROFILE'. Run: xcrun notarytool store-credentials $NOTARY_PROFILE --key AuthKey_XXX.p8 --key-id KEYID --issuer ISSUER"

[ -f "$SPARKLE_KEY" ] || die "Missing $SPARKLE_KEY — without it, installed copies reject the update."
SIGN_UPDATE="$(find "$HOME/Library/Developer/Xcode/DerivedData/Haze-"*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -1)"
[ -x "$SIGN_UPDATE" ] || die "Sparkle's sign_update not found — run 'make build' once to resolve the package."

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
  build > "$OUT/build.log" 2>&1 || { tail -30 "$OUT/build.log"; die "Build failed — full log: $OUT/build.log"; }

codesign --verify --deep --strict "$APP" || die "The build is not properly signed."
codesign -dv --verbose=2 "$APP" 2>&1 | grep -q "Authority=Developer ID Application" \
  || die "The build is not Developer ID-signed — an ad-hoc release can never auto-update."

# ---------------------------------------------------------------- notarize
step "Notarizing (Apple usually answers in 1-5 min)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait \
  || die "Notarization was rejected — see the log above."
xcrun stapler staple "$APP" || die "Stapling failed."
spctl --assess --type execute --verbose=2 "$APP" 2>&1 | grep -q "accepted" \
  || die "Gatekeeper still rejects the app after notarization."
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
echo "Note: anyone still on an ad-hoc build (v0.1.0) will NOT get this update"
echo "automatically — they have to download the DMG once by hand."
