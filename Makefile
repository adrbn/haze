PROJECT := Haze.xcodeproj
SCHEME  := Haze
DEST    := platform=macOS,arch=arm64
DEBUG_APP = $(shell find $(HOME)/Library/Developer/Xcode/DerivedData/Haze-*/Build/Products/Debug -maxdepth 1 -name Haze.app 2>/dev/null | head -1)
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
	@rm -rf "$(SAVER_DIR)/HazeSaver.saver"
	@cp -R "$(DEBUG_APP)/Contents/Resources/HazeSaver.saver" "$(SAVER_DIR)/"
	@echo "Installed to $(SAVER_DIR)/HazeSaver.saver — pick it in Screen Saver settings"

clean:
	rm -rf Haze.xcodeproj build
	@echo "Cleaned generated project (DerivedData left intact)"
