# Scratio

Menu-bar macOS app for screenshots with preset aspect ratios (16:9, 9:16, 1:1, and more). Captures copy to the clipboard and appear in an in-app gallery.

## Requirements

- macOS 15.7+
- Xcode 16+ (project created with Xcode 26 tooling)
- Screen Recording permission (prompted on first capture)

## Quick start

1. Open `scratio.xcodeproj` in Xcode
2. Select the **scratio** scheme and **My Mac**
3. Press **⌘R** to run
4. Use the menu bar camera icon → **New Capture**, or the default hotkey **⌘⇧6**

A local beginner guide (Swift for TypeScript developers, debug, build, architecture) lives at `Docs/GUIDE.md` (gitignored; generated for local use).

## Features

- Native-style dimmed overlay with dashed selection and rule-of-thirds grid
- Aspect ratios: 1:1, 16:9, 9:16, 4:3, 3:4, 3:2, 2:3, or Independent (freeform)
- Capture modes: selection, window, entire screen
- Toolbar selects mode/ratio without capturing; camera button / Return captures; Esc cancels
- Gallery sorted by created date (newest first by default)
- Configurable global hotkey in Settings
- Storage: `~/Library/Application Support/scratio/Screenshots/`
