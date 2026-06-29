#!/usr/bin/env bash
# Set the repository description and topics (keywords) for discoverability.
# Run once (needs `gh` authenticated): ./scripts/github-meta.sh
set -euo pipefail

REPO="paolobozzola/glyph"

gh repo edit "$REPO" \
  --description "A pure WYSIWYG Markdown editor for macOS — edit rich, save plain." \
  --homepage "https://www.buymeacoffee.com/paolobozzola"

gh repo edit "$REPO" \
  --add-topic markdown \
  --add-topic markdown-editor \
  --add-topic wysiwyg-editor \
  --add-topic macos-app \
  --add-topic milkdown \
  --add-topic prosemirror \
  --add-topic commonmark \
  --add-topic gfm \
  --add-topic text-editor

echo "✅ Description and topics updated for $REPO"
