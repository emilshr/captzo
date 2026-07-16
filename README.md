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
- Multi-display: drag the selection grid and capture toolbar across screens
- Session restore: last mode, aspect ratio, selection rect, and toolbar position
- Toolbar selects mode/ratio without capturing; camera button / Return captures; Esc cancels
- Gallery sorted by created date (newest first by default)
- Configurable global hotkey in Settings
- Storage: `~/Library/Application Support/scratio/Screenshots/`

## Install with Homebrew

After a notarized GitHub release exists and the tap is published:

```bash
brew tap emilshr/scratio
brew install --cask scratio
```

Then grant **Screen Recording** under System Settings → Privacy & Security.

**Full setup** (Developer ID, notarization secrets, tap repo, release checklist): [`docs/homebrew-setup.md`](docs/homebrew-setup.md).

## Release (DMG + notarization)

```bash
git tag v1.0.0
git push origin v1.0.0
```

That runs [`.github/workflows/release-dmg.yml`](.github/workflows/release-dmg.yml). See [`docs/homebrew-setup.md`](docs/homebrew-setup.md) for secrets and local packaging.

## Development

```bash
# Unit tests
xcodebuild test -scheme scratio -destination 'platform=macOS' -only-testing:scratioTests
```

### Screen Recording permission (debugging)

macOS ties Screen Recording to your app’s code signature and process. After granting or revoking permission, **quit Scratio and relaunch** (in Xcode: Stop, then Run again) before capture will work.

Recommended workflow:

1. Use **Apple Development** signing with a stable team (not ad-hoc / “Sign to Run Locally”) so TCC remembers the app across builds.
2. Grant Screen Recording once, Stop in Xcode, Run again, and leave the toggle on.
3. To reset for testing: `tccutil reset ScreenCapture emilshr.scratio`, then Stop → Run → grant → Stop → Run again.

Avoid repeatedly toggling the permission checkbox during a debug session; appearing in the list does not mean the current process has access.
