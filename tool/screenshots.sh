#!/usr/bin/env bash
# Renders the screenshots in docs/screenshots (see
# test/screenshots/screenshots.dart). Run from the project root.
set -euo pipefail

fonts=test/screenshots/fonts
mkdir -p "$fonts"

# Rubik in the two weights the app uses. These are the very files the
# google_fonts package downloads at runtime.
while read -r weight hash; do
  file="$fonts/Rubik-$weight.ttf"
  [ -s "$file" ] ||
    curl -fsSL -o "$file" "https://fonts.gstatic.com/s/a/$hash.ttf"
done <<'FONTS'
400 db4588883899babda86dc335c84b4876cd9afaedcd845830e9ac4d11c7fbed97
700 9727be7df420f705fcf478126f40b1f297c381af89cc3db35419769274aabf4a
FONTS

# Tests have no system fonts. Emoji need a font of their own, and so does
# any Arabic character that Rubik does not cover.
arabic="$fonts/NotoSansArabic-400.ttf"
[ -s "$arabic" ] ||
  curl -fsSL -o "$arabic" \
    https://fonts.gstatic.com/s/a/3d0a42565e116e088231be26dee07e2383e9c0744ac99be79cb2d871fba18161.ttf

emoji="$fonts/NotoColorEmoji.ttf"
[ -s "$emoji" ] ||
  curl -fsSL -o "$emoji" \
    https://github.com/googlefonts/noto-emoji/raw/99701e07d3d1fe1bdbcdb14964547f0fd592966f/2D/fonts/NotoColorEmoji.ttf

flutter test --update-goldens test/screenshots/screenshots.dart
