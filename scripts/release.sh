#!/usr/bin/env bash
#
# Builds LF-Paper.zip and its Homebrew cask.
#
set -euo pipefail

TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-LF-Paper-notary}"
REPOSITORY="${REPOSITORY:-alifu/LF-Paper}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/release"
ARCHIVE="$BUILD/LF-Paper.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/LF-Paper.app"
ZIP="$BUILD/LF-Paper.zip"
CASK="$BUILD/lf-paper.rb"
SETTINGS="$(xcodebuild -project "$ROOT/LF-Paper.xcodeproj" -scheme LF-Paper -configuration Release -showBuildSettings 2>/dev/null)"
setting() { awk -F' = ' -v key="$1" '$1 ~ "^ *" key "$" { print $2; exit }' <<<"$SETTINGS"; }
VERSION="$(setting MARKETING_VERSION)"
BUNDLE_ID="$(setting PRODUCT_BUNDLE_IDENTIFIER)"

step() { printf '\n==> %s\n' "$*"; }

step "Cleaning $BUILD"
rm -rf "$BUILD"
mkdir -p "$BUILD"

if [[ -n "$TEAM_ID" ]]; then
  step "Archiving LF-Paper $VERSION (Release, Developer ID team $TEAM_ID)"
  xcodebuild archive \
    -project "$ROOT/LF-Paper.xcodeproj" \
    -scheme LF-Paper \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -skipPackagePluginValidation \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic

  step "Exporting with Developer ID"
  cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist"
else
  step "Archiving LF-Paper $VERSION (Release, signed ad hoc, not notarized)"
  xcodebuild archive \
    -project "$ROOT/LF-Paper.xcodeproj" \
    -scheme LF-Paper \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -skipPackagePluginValidation \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM=
  mkdir -p "$EXPORT"
  ditto "$ARCHIVE/Products/Applications/LF-Paper.app" "$APP"
fi

step "Checking the signature"
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ -n "$TEAM_ID" ]]; then
  step "Notarizing (this can take a few minutes)"
  ditto -c -k --keepParent "$APP" "$BUILD/notarize.zip"
  xcrun notarytool submit "$BUILD/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$BUILD/notarize.zip"

  step "Gatekeeper check"
  spctl --assess --type execute --verbose=2 "$APP"
fi

step "Zipping $ZIP"
# ditto keeps the signature, extended attributes and symlinks intact (plain zip can break them).
ditto -c -k --keepParent "$APP" "$ZIP"
SHA256="$(shasum -a 256 "$ZIP" | awk '{ print $1 }')"

step "Writing the Homebrew cask"
cat > "$CASK" <<RUBY
cask "lf-paper" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPOSITORY/releases/download/#{version}/LF-Paper.zip"
  name "LF-Paper"
  desc "Markdown and JSON workbench with live preview, validation and comparison"
  homepage "https://github.com/$REPOSITORY"

  depends_on macos: ">= :sequoia"

  app "LF-Paper.app"

  uninstall quit: "$BUNDLE_ID"

  zap trash: [
    "~/Library/Application Scripts/$BUNDLE_ID",
    "~/Library/Containers/$BUNDLE_ID",
  ]
end
RUBY

printf '\nDone: %s (sha256 %s)\n' "$ZIP" "$SHA256"
cat "$CASK"
