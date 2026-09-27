# LF-Paper

A native macOS workbench for Markdown and JSON: open a folder, edit files in tabs with syntax highlighting,
preview Markdown live, validate and format JSON, browse it as a tree, and compare two JSON documents.
It also has a scratchpad for throwaway text, like a prompt you're about to paste into an AI agent.

Requires macOS 26.5 or later.

## Install

With [Homebrew](https://brew.sh):

```bash
brew install --cask alifu/tap/lf-paper
```

Then open it from Applications, or run:

```bash
open -a LF-Paper
```

### "Apple cannot check it for malicious software"

LF-Paper isn't notarized by Apple, so macOS asks before the first launch:

1. Open **System Settings** → **Privacy & Security**.
2. Next to the message about LF-Paper, click **Open Anyway**.
3. Confirm with **Open**.

macOS remembers this, so it only happens once per version.

### Manual installation

Download `LF-Paper.zip` from the [latest release](https://github.com/alifu/LF-Paper/releases/latest),
unzip it and move `LF-Paper.app` to Applications.

## Update

```bash
brew upgrade --cask lf-paper
```

## Uninstall

```bash
brew uninstall --cask lf-paper
```

To also remove its settings and data:

```bash
brew uninstall --zap --cask lf-paper
```

## Development

Open `LF-Paper.xcodeproj` in Xcode 26.5 and run the `LF-Paper` scheme.

Unit tests (the UI tests take over the mouse and keyboard, so run those by hand):

```bash
xcodebuild test -project LF-Paper.xcodeproj -scheme LF-Paper -destination 'platform=macOS' -only-testing:LF-PaperTests -skipPackagePluginValidation
```

SwiftLint runs as a build plugin (only the file-length rule, 800 lines). Xcode asks once to trust it;
command-line builds need `-skipPackagePluginValidation`, as above.

### Releasing

1. Raise `MARKETING_VERSION` (Homebrew only sees a new version number).
2. Run `scripts/release.sh`. It builds `build/release/LF-Paper.zip` and writes the matching cask to
   `build/release/lf-paper.rb`. With `TEAM_ID=…` it signs with Developer ID and notarizes instead.
3. Create a GitHub release tagged with the version (for example `1.0`) and attach `LF-Paper.zip`.
4. Copy `lf-paper.rb` to `Casks/lf-paper.rb` in [alifu/homebrew-tap](https://github.com/alifu/homebrew-tap) and push.

## Credits

- **Hyrule** and **Hyrule Light** editor themes from [Rainglow](https://rainglow.io) by Dayle Rees (MIT License).
- [swift-cmark](https://github.com/swiftlang/swift-cmark) for Markdown (BSD 2-Clause License).
- [Yams](https://github.com/jpsim/Yams) for YAML (MIT License).
