# Glyph build glue. See docs/SETUP.md.
.PHONY: all web project open clean

all: web project ## Build editor bundle + generate Xcode project

web: ## Build the Milkdown editor bundle -> Glyph/Resources/editor/
	cd web && npm install && npm run build

project: ## Generate Glyph.xcodeproj from project.yml (needs xcodegen)
	xcodegen generate

open: all ## Build everything and open the project in Xcode
	open Glyph.xcodeproj

clean: ## Remove generated artifacts
	rm -rf web/node_modules Glyph/Resources/editor Glyph.xcodeproj
