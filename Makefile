PROJECT := Sleepi.xcodeproj
SCHEME  := Sleepi
DEST    := platform=macOS,arch=arm64
DEBUG_APP = $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/Sleepi-*/Build/Products/Debug -maxdepth 1 -name Sleepi.app 2>/dev/null | head -1)
SAVER_DIR := $(HOME)/Library/Screen Savers

.PHONY: all generate build test release run install-saver clean

all: build

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' test

release: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DEST)' build

run: build
	@open "$(DEBUG_APP)" && echo "Launched $(DEBUG_APP) (look for 🌙 in the menu bar)"

install-saver: build
	@mkdir -p "$(SAVER_DIR)"
	@rm -rf "$(SAVER_DIR)/SleepiSaver.saver"
	@cp -R "$(DEBUG_APP)/Contents/Resources/SleepiSaver.saver" "$(SAVER_DIR)/"
	@echo "Installed to $(SAVER_DIR)/SleepiSaver.saver — pick it in Screen Saver settings"

clean:
	rm -rf Sleepi.xcodeproj build
	@echo "Cleaned generated project (DerivedData left intact)"
