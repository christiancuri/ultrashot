# UltraShot for macOS. Requires Xcode, xcodegen and swiftlint (Homebrew).
PROJECT      := UltraShot.xcodeproj
SCHEME       := UltraShot
DERIVED_DATA := build/DerivedData
APP          := $(DERIVED_DATA)/Build/Products/Debug/UltraShot.app
KIT          := Packages/UltraShotKit

# Development team for signing: $TEAM_ID, else the gitignored .team-id file. Never echoed.
TEAM_ID ?= $(strip $(shell cat .team-id 2>/dev/null))

.PHONY: gen build run test lint release publish clean

gen:
	xcodegen generate --spec project.yml

# Signed Debug build (Apple Development identity, manual style, no provisioning profile),
# Apple Silicon only. Screen Recording grants are tied to the signature, so it must be signed.
# The xcodebuild line is not echoed because it carries the team id.
build: gen
	@test -n "$(TEAM_ID)" || { echo "error: set TEAM_ID or create .team-id with your Apple development team id"; exit 1; }
	@echo "xcodebuild -scheme $(SCHEME) -configuration Debug (signed)"
	@set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED_DATA) \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" PROVISIONING_PROFILE_SPECIFIER= \
		DEVELOPMENT_TEAM="$(TEAM_ID)" build 2>&1 | sed "s/$(TEAM_ID)/<team>/g"

run: build
	-@pkill -x UltraShot 2>/dev/null; true
	open "$(APP)"

# All logic (and its tests) lives in the UltraShotKit package.
test:
	cd "$(KIT)" && swift test

lint:
	swiftlint lint --strict

# Developer ID signed, notarized and stapled DMG + zip + checksums.txt in build/release/dist
# (nothing is uploaded). The team id reaches the script through the environment only.
# Usage: make release VERSION=x.y.z [BUILD=n] [SKIP_NOTARIZE=1]
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z [BUILD=n] [SKIP_NOTARIZE=1]"; exit 1; }
	@echo "scripts/release.sh $(VERSION)$(if $(BUILD), --build $(BUILD))$(if $(filter 1,$(SKIP_NOTARIZE)), --skip-notarize)"
	@TEAM_ID="$(TEAM_ID)" scripts/release.sh "$(VERSION)" $(if $(BUILD),--build "$(BUILD)") \
		$(if $(filter 1,$(SKIP_NOTARIZE)),--skip-notarize)

# Build + notarize (scripts/release.sh), tag v<x.y.z>, push the tag and create the GitHub
# release from the CHANGELOG.md section. DRY_RUN=1 only checks and prints the plan.
# Usage: make publish VERSION=x.y.z [YES=1] [DRY_RUN=1]
publish:
	@test -n "$(VERSION)" || { echo "usage: make publish VERSION=x.y.z [YES=1] [DRY_RUN=1]"; exit 1; }
	@echo "scripts/publish.sh (VERSION=$(VERSION) YES=$(YES) DRY_RUN=$(DRY_RUN))"
	@TEAM_ID="$(TEAM_ID)" VERSION="$(VERSION)" YES="$(YES)" DRY_RUN="$(DRY_RUN)" scripts/publish.sh

clean:
	rm -rf build $(PROJECT) $(KIT)/.build
