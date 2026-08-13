PROJECT := Haze.xcodeproj
SCHEME  := Haze
DEST    := platform=macOS,arch=arm64
DEBUG_APP = $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/Haze-*/Build/Products/Debug -maxdepth 1 -name Haze.app 2>/dev/null | head -1)
RELEASE_APP = $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/Haze-*/Build/Products/Release -maxdepth 1 -name Haze.app 2>/dev/null | head -1)
SAVER_DIR := $(HOME)/Library/Screen Savers

# Distribution signing. Prefix-matched against the keychain, so no personal
# details live in the repo; override either on the command line.
#   make install SIGN_ID="Apple Development"
SIGN_ID ?= Developer ID Application
TEAM_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep -m1 "$(SIGN_ID)" | sed -n 's/.*(\([A-Z0-9]\{10\}\))".*/\1/p')
SIGNED_FLAGS = HAZE_CODE_SIGN_IDENTITY="$(SIGN_ID)" HAZE_DEVELOPMENT_TEAM="$(TEAM_ID)" \
               OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGNING_REQUIRED=YES

# Version stamping, taken from git like the release does. project.yml carries a
# fixed placeholder, so without this an installed local build declares itself
# older than the latest published release — and Sparkle then offers that release
# as an "update" to a copy that is actually newer.
VERSION ?= $(patsubst v%,%,$(shell git describe --tags --abbrev=0 2>/dev/null))
BUILD   ?= $(shell git rev-list --count HEAD 2>/dev/null)
STAMP    = $(if $(VERSION),MARKETING_VERSION="$(VERSION)" CURRENT_PROJECT_VERSION="$(BUILD)",)

# Keychain profile, created once with an App Store Connect API key:
#   xcrun notarytool store-credentials haze --key AuthKey_XXX.p8 --key-id KEYID --issuer ISSUER
NOTARY_PROFILE ?= haze

.PHONY: all generate build test release release-signed release-publish run install install-saver notarize verify-signature clean

all: build

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' test

release: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DEST)' build

## Release build signed with the Developer ID certificate (hardened runtime on,
## secure timestamp) — the prerequisite for notarizing.
release-signed: generate
	@test -n "$(TEAM_ID)" || { echo "No '$(SIGN_ID)' certificate in the keychain."; exit 1; }
	@echo "Signing as '$(SIGN_ID)' (team $(TEAM_ID))"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DEST)' \
		$(SIGNED_FLAGS) $(STAMP) CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
	@APP=$$(find $(HOME)/Library/Developer/Xcode/DerivedData/Haze-*/Build/Products/Release \
	          -maxdepth 1 -name Haze.app 2>/dev/null | sed -n '1p'); \
	 test -n "$$APP" || { echo "No Release Haze.app found after the build"; exit 1; }; \
	 ./scripts/sign_sparkle.sh "$$APP" "$(SIGN_ID)"

run: build
	@open "$(DEBUG_APP)" && echo "Launched $(DEBUG_APP) (look for the Haze glyph in the menu bar)"

## Replace /Applications/Haze.app with a freshly built, Developer ID-signed copy
## and relaunch it. A stable signing identity means macOS keeps the permissions
## it already granted instead of re-prompting after every build.
install: release-signed
	@test -n "$(RELEASE_APP)" || { echo "No Release Haze.app found"; exit 1; }
	@osascript -e 'quit app "Haze"' 2>/dev/null || true
	@sleep 1
	@rm -rf /Applications/Haze.app
	@cp -R "$(RELEASE_APP)" /Applications/
	@open /Applications/Haze.app
	@echo "Installed and relaunched /Applications/Haze.app"

verify-signature:
	@APP="$${APP:-/Applications/Haze.app}"; \
	echo "== $$APP =="; \
	codesign --verify --deep --strict --verbose=2 "$$APP" && echo "signature OK"; \
	codesign -dv --verbose=4 "$$APP" 2>&1 | grep -E "Authority|TeamIdentifier|flags"; \
	spctl --assess --type execute --verbose=4 "$$APP" || \
	  echo "(not accepted by Gatekeeper yet — notarize + staple for that)"

## Submit the signed Release build to Apple and staple the ticket. Needs the
## notarytool keychain profile above; it is never read or stored by the build.
notarize: release-signed
	@test -n "$(RELEASE_APP)" || { echo "No Release Haze.app found"; exit 1; }
	@rm -f Haze-notarize.zip
	ditto -c -k --sequesterRsrc --keepParent "$(RELEASE_APP)" Haze-notarize.zip
	xcrun notarytool submit Haze-notarize.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(RELEASE_APP)"
	@rm -f Haze-notarize.zip
	@$(MAKE) verify-signature APP="$(RELEASE_APP)"

## Cut a release from this Mac: signed, notarized, stapled, DMG + Sparkle
## archive + appcast, published to GitHub. Needs only the notary profile above —
## the certificate is already in your keychain, which is the whole reason this
## is simpler than the CI path.
##   make release-publish TAG=v0.1.4
release-publish: generate
	@test -n "$(TAG)" || { echo "Usage: make release-publish TAG=v0.1.4"; exit 1; }
	@NOTARY_PROFILE="$(NOTARY_PROFILE)" SIGN_ID="$(SIGN_ID)" ./scripts/release.sh "$(TAG)"

install-saver: build
	@mkdir -p "$(SAVER_DIR)"
	@rm -rf "$(SAVER_DIR)/HazeSaver.saver"
	@cp -R "$(DEBUG_APP)/Contents/Resources/HazeSaver.saver" "$(SAVER_DIR)/"
	@echo "Installed to $(SAVER_DIR)/HazeSaver.saver — pick it in Screen Saver settings"

clean:
	rm -rf Haze.xcodeproj build
	@echo "Cleaned generated project (DerivedData left intact)"
