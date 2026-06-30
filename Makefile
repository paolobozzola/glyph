# Glyph build glue. See docs/SETUP.md.
.PHONY: all web project open run clean

all: web project ## Build editor bundle + generate Xcode project

web: ## Build the editor + Quick Look preview bundles
	cd web && npm install && npm run build
	cd web-preview && npm install && npm run build

project: ## Generate Glyph.xcodeproj from project.yml (needs xcodegen)
	xcodegen generate

open: all ## Build everything and open the project in Xcode
	open Glyph.xcodeproj

run: ## Recompile the app (Debug) and launch it with the Welcome sample
	xcodebuild -project Glyph.xcodeproj -scheme Glyph -configuration Debug \
		-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build -quiet
	@pkill -x Glyph 2>/dev/null || true
	@APP="$$(ls -dt ~/Library/Developer/Xcode/DerivedData/Glyph-*/Build/Products/Debug/Glyph.app | head -1)"; \
	 SAMPLE="$${TMPDIR:-/tmp}/Glyph-Welcome.md"; \
	 cp samples/Welcome.md "$$SAMPLE"; \
	 open -a "$$APP" "$$SAMPLE"

dist: all ## Sign (Developer ID), notarize, and build dist/Glyph.dmg (see docs/RELEASE.md)
	DEV_ID="$(DEV_ID)" NOTARY_PROFILE="$(NOTARY_PROFILE)" ./scripts/package.sh

clean: ## Remove generated artifacts
	rm -rf web/node_modules web-preview/node_modules \
	       Glyph/Resources/editor QuickLook/Resources/preview Glyph.xcodeproj
