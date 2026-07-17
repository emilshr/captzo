import CoreGraphics
import Foundation
import Testing
@testable import Captzo

struct AspectRatioTests {
    @Test func aspectRatioOneToOneIsLocked() {
        #expect(AspectRatioOption.oneToOne.isLocked)
        #expect(AspectRatioOption.oneToOne.ratio == 1)
    }

    @Test func freeformAspectRatioIsUnlocked() {
        #expect(AspectRatioOption.freeform.isLocked == false)
        #expect(AspectRatioOption.freeform.ratio == nil)
        #expect(AspectRatioOption.freeform.rawValue == "Freeform")
    }

    @Test func fromPersistedMapsLegacyIndependentToFreeform() {
        #expect(AspectRatioOption.fromPersisted("Independent") == .freeform)
        #expect(AspectRatioOption.fromPersisted("Freeform") == .freeform)
        #expect(AspectRatioOption.fromPersisted("1:1") == .oneToOne)
        #expect(AspectRatioOption.fromPersisted(nil) == nil)
        #expect(AspectRatioOption.fromPersisted("unknown") == nil)
    }

    @Test func constrainKeepsSixteenByNine() {
        let rect = CGRect(x: 0, y: 0, width: 320, height: 320)
        let constrained = CaptureSessionState.constrain(rect, to: .sixteenToNine)
        let ratio = constrained.width / constrained.height
        #expect(abs(ratio - (16.0 / 9.0)) < 0.01)
    }

    @Test(arguments: [
        AspectRatioOption.oneToOne,
        .sixteenToNine,
        .nineToSixteen,
        .fourToThree,
        .threeToFour,
    ])
    func lockedRatiosHavePositiveRatio(_ option: AspectRatioOption) throws {
        let ratio = try #require(option.ratio)
        #expect(ratio > 0)
        #expect(option.isLocked)
    }

    @MainActor
    @Test func setAspectRatioFromWindowModeSwitchesToSelection() {
        let session = CaptureSessionState()
        session.mode = .window
        session.setAspectRatio(.sixteenToNine)
        #expect(session.mode == .selection)
        #expect(session.aspectRatio == .sixteenToNine)
    }

    @MainActor
    @Test func setAspectRatioFromDisplayModeSwitchesToSelection() {
        let session = CaptureSessionState()
        session.mode = .display
        session.setAspectRatio(.freeform)
        #expect(session.mode == .selection)
        #expect(session.aspectRatio == .freeform)
    }

    @MainActor
    @Test func setAspectRatioInSelectionModeKeepsSelection() {
        let session = CaptureSessionState()
        session.mode = .selection
        session.setAspectRatio(.nineToSixteen)
        #expect(session.mode == .selection)
        #expect(session.aspectRatio == .nineToSixteen)
    }
}

struct CoordinateConversionTests {
    @Test func primaryScreenMaxYIsPositive() {
        #expect(ScreenshotCaptureService.primaryScreenMaxY() > 0)
    }

    @Test func convertToCaptureSpaceFlipsY() {
        let primaryMaxY: CGFloat = 1080
        let appKit = CGRect(x: 10, y: 20, width: 100, height: 50)
        let converted = ScreenGeometry.convertToCaptureSpace(appKit, primaryMaxY: primaryMaxY)
        #expect(converted.origin.x == 10)
        #expect(converted.width == 100)
        #expect(converted.height == 50)
        #expect(abs(converted.origin.y - (primaryMaxY - 20 - 50)) < 0.001)
    }

    @Test func convertToCaptureSpaceHandlesDisplayAbovePrimary() {
        // Secondary display stacked above primary: AppKit Y can exceed primaryMaxY → Quartz Y negative.
        let primaryMaxY: CGFloat = 1080
        let appKit = CGRect(x: 0, y: 1100, width: 200, height: 100)
        let converted = ScreenGeometry.convertToCaptureSpace(appKit, primaryMaxY: primaryMaxY)
        #expect(converted.origin.y < 0)
        #expect(abs(converted.origin.y - (1080 - 1100 - 100)) < 0.001)
    }

    @Test func scWindowFrameRoundTrip() {
        let primaryMaxY: CGFloat = 900
        let scFrame = CGRect(x: 50, y: 100, width: 300, height: 200)
        let appKit = ScreenGeometry.convertSCWindowFrameToAppKit(scFrame, primaryMaxY: primaryMaxY)
        let back = ScreenGeometry.convertToCaptureSpace(appKit, primaryMaxY: primaryMaxY)
        #expect(abs(back.origin.x - scFrame.origin.x) < 0.001)
        #expect(abs(back.origin.y - scFrame.origin.y) < 0.001)
        #expect(abs(back.width - scFrame.width) < 0.001)
        #expect(abs(back.height - scFrame.height) < 0.001)
    }

    @Test func serviceConvertMatchesGeometryHelper() {
        let primaryMaxY = ScreenshotCaptureService.primaryScreenMaxY()
        let appKit = CGRect(x: 10, y: 20, width: 100, height: 50)
        let viaService = ScreenshotCaptureService.convertToCaptureSpace(appKit)
        let viaHelper = ScreenGeometry.convertToCaptureSpace(appKit, primaryMaxY: primaryMaxY)
        #expect(viaService == viaHelper)
    }
}

struct VirtualDesktopClampTests {
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test func unionSpansBothDisplays() {
        let union = ScreenGeometry.virtualDesktopUnion(of: [primary, secondary])
        #expect(union.minX == 0)
        #expect(union.maxX == 3360)
        #expect(union.height == 1080)
    }

    @Test func clampAllowsCrossScreenMove() {
        let desktop = ScreenGeometry.virtualDesktopUnion(of: [primary, secondary])
        let rect = CGRect(x: 1300, y: 100, width: 200, height: 150)
        let clamped = ScreenGeometry.clampRect(rect, to: desktop)
        #expect(clamped.origin.x == 1300)
        #expect(clamped.maxX <= desktop.maxX)
        #expect(clamped.intersects(secondary) || clamped.intersects(primary))
    }

    @Test func clampEnforcesMinimumSize() {
        let desktop = primary
        let tiny = CGRect(x: 10, y: 10, width: 5, height: 5)
        let clamped = ScreenGeometry.clampRect(tiny, to: desktop)
        #expect(clamped.width >= ScreenGeometry.minimumSelectionSide)
        #expect(clamped.height >= ScreenGeometry.minimumSelectionSide)
    }

    @Test func clampKeepsRectInsideBounds() {
        let desktop = primary
        let overflow = CGRect(x: 1400, y: 850, width: 200, height: 200)
        let clamped = ScreenGeometry.clampRect(overflow, to: desktop)
        #expect(clamped.maxX <= desktop.maxX)
        #expect(clamped.maxY <= desktop.maxY)
        #expect(clamped.minX >= desktop.minX)
        #expect(clamped.minY >= desktop.minY)
    }

    @Test func validSelectionRequiresIntersectionAndSize() {
        let desktop = ScreenGeometry.virtualDesktopUnion(of: [primary, secondary])
        #expect(ScreenGeometry.isValidSelection(CGRect(x: 10, y: 10, width: 100, height: 100), in: desktop))
        #expect(!ScreenGeometry.isValidSelection(CGRect(x: 10, y: 10, width: 5, height: 100), in: desktop))
        #expect(!ScreenGeometry.isValidSelection(CGRect(x: 10_000, y: 10_000, width: 100, height: 100), in: desktop))
    }

    @Test func emptyDesktopUnionIsZero() {
        #expect(ScreenGeometry.virtualDesktopUnion(of: []) == .zero)
    }

    @Test func clampToScreensSnapsOutOfGap() {
        // Gap between displays: [0,1000] then [1200,2200]
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1200, y: 0, width: 1000, height: 800)
        let inGap = CGRect(x: 1050, y: 100, width: 100, height: 100)
        let clamped = ScreenGeometry.clampRect(inGap, toScreens: [left, right])
        let center = CGPoint(x: clamped.midX, y: clamped.midY)
        #expect(left.contains(center) || right.contains(center))
    }

    @Test func validSelectionOnScreensRequiresRealIntersection() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1200, y: 0, width: 1000, height: 800)
        #expect(ScreenGeometry.isValidSelection(CGRect(x: 10, y: 10, width: 100, height: 100), onScreens: [left, right]))
        #expect(!ScreenGeometry.isValidSelection(CGRect(x: 1050, y: 10, width: 100, height: 100), onScreens: [left, right]))
    }
}

@Suite(.serialized)
struct AppPreferencesTests {
    @Test func captureModeRoundTrip() throws {
        let suiteName = "captzo.tests.prefs.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer {
            suite.removePersistentDomain(forName: suiteName)
            AppPreferences.defaults = .standard
        }
        AppPreferences.defaults = suite

        AppPreferences.captureMode = .window
        #expect(AppPreferences.captureMode == .window)
        AppPreferences.captureMode = .display
        #expect(AppPreferences.captureMode == .display)
    }

    @Test func selectionRectRoundTrip() throws {
        let suiteName = "captzo.tests.prefs.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer {
            suite.removePersistentDomain(forName: suiteName)
            AppPreferences.defaults = .standard
        }
        AppPreferences.defaults = suite

        let rect = CGRect(x: 12.5, y: 40, width: 320, height: 180)
        AppPreferences.selectionRect = rect
        let loaded = try #require(AppPreferences.selectionRect)
        #expect(abs(loaded.origin.x - rect.origin.x) < 0.001)
        #expect(abs(loaded.origin.y - rect.origin.y) < 0.001)
        #expect(abs(loaded.width - rect.width) < 0.001)
        #expect(abs(loaded.height - rect.height) < 0.001)

        AppPreferences.selectionRect = nil
        #expect(AppPreferences.selectionRect == nil)
    }

    @Test func toolbarOriginRoundTrip() throws {
        let suiteName = "captzo.tests.prefs.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer {
            suite.removePersistentDomain(forName: suiteName)
            AppPreferences.defaults = .standard
        }
        AppPreferences.defaults = suite

        let point = CGPoint(x: 100, y: 48)
        AppPreferences.toolbarOrigin = point
        let loaded = try #require(AppPreferences.toolbarOrigin)
        #expect(abs(loaded.x - point.x) < 0.001)
        #expect(abs(loaded.y - point.y) < 0.001)
    }

    @Test func aspectRatioMigratesLegacyIndependent() throws {
        let suiteName = "captzo.tests.prefs.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer {
            suite.removePersistentDomain(forName: suiteName)
            AppPreferences.defaults = .standard
        }
        AppPreferences.defaults = suite

        suite.set(AspectRatioOption.legacyIndependentRawValue, forKey: AppPreferences.aspectRatioKey)
        #expect(AppPreferences.aspectRatio == .freeform)

        AppPreferences.aspectRatio = .freeform
        #expect(suite.string(forKey: AppPreferences.aspectRatioKey) == "Freeform")
    }

    @Test func badgeColorReadsLegacyIndependentKey() throws {
        let suiteName = "captzo.tests.prefs.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer {
            suite.removePersistentDomain(forName: suiteName)
            AppPreferences.defaults = .standard
        }
        AppPreferences.defaults = suite

        suite.set(
            [AspectRatioOption.legacyIndependentRawValue: "AABBCC"],
            forKey: AppPreferences.aspectRatioBadgeColorsKey
        )
        #expect(AppPreferences.badgeColorHex(for: .freeform) == "AABBCC")

        AppPreferences.setBadgeColorHex("112233", for: .freeform)
        let overrides = suite.dictionary(forKey: AppPreferences.aspectRatioBadgeColorsKey) as? [String: String]
        #expect(overrides?["Freeform"] == "112233")
        #expect(overrides?[AspectRatioOption.legacyIndependentRawValue] == nil)
    }
}

struct WindowCaptureConfigTests {
    @Test func pixelSizeFromContentRectAndScale() throws {
        let size = try #require(
            ScreenGeometry.capturePixelSize(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                pointPixelScale: 2
            )
        )
        #expect(size.width == 800)
        #expect(size.height == 600)
    }

    @Test func pixelSizeEnforcesMinimumOne() throws {
        let size = try #require(
            ScreenGeometry.capturePixelSize(
                contentRect: CGRect(x: 0, y: 0, width: 0.2, height: 0.2),
                pointPixelScale: 1
            )
        )
        #expect(size.width == 1)
        #expect(size.height == 1)
    }

    @Test func pixelSizeRejectsZeroFrame() {
        #expect(
            ScreenGeometry.capturePixelSize(
                contentRect: .zero,
                pointPixelScale: 2
            ) == nil
        )
    }

    @Test func pixelSizeRejectsZeroScale() {
        #expect(
            ScreenGeometry.capturePixelSize(
                contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                pointPixelScale: 0
            ) == nil
        )
    }
}

struct WindowHitTestingTests {
    @Test func frontmostPrefersLowerLayer() {
        let back = ScreenGeometry.WindowHitCandidate(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 200, height: 200),
            windowLayer: 5,
            sourceIndex: 0
        )
        let front = ScreenGeometry.WindowHitCandidate(
            id: 2,
            frame: CGRect(x: 50, y: 50, width: 100, height: 100),
            windowLayer: 0,
            sourceIndex: 1
        )
        let hit = ScreenGeometry.frontmostWindow(
            at: CGPoint(x: 75, y: 75),
            in: [back, front]
        )
        #expect(hit?.id == 2)
    }

    @Test func frontmostPrefersLaterSourceIndexWhenLayersTie() {
        let earlier = ScreenGeometry.WindowHitCandidate(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 300, height: 300),
            windowLayer: 0,
            sourceIndex: 0
        )
        let later = ScreenGeometry.WindowHitCandidate(
            id: 20,
            frame: CGRect(x: 0, y: 0, width: 200, height: 200),
            windowLayer: 0,
            sourceIndex: 3
        )
        let hit = ScreenGeometry.frontmostWindow(
            at: CGPoint(x: 50, y: 50),
            in: [earlier, later]
        )
        #expect(hit?.id == 20)
    }

    @Test func frontmostReturnsNilOutsideAllFrames() {
        let candidate = ScreenGeometry.WindowHitCandidate(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            windowLayer: 0,
            sourceIndex: 0
        )
        let hit = ScreenGeometry.frontmostWindow(
            at: CGPoint(x: 500, y: 500),
            in: [candidate]
        )
        #expect(hit == nil)
    }

    @Test func frontmostWindowIDPrefersCGWindowOrder() {
        let back = ScreenGeometry.WindowHitCandidate(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 300, height: 300),
            windowLayer: 0,
            sourceIndex: 0
        )
        let front = ScreenGeometry.WindowHitCandidate(
            id: 2,
            frame: CGRect(x: 50, y: 50, width: 200, height: 200),
            windowLayer: 0,
            sourceIndex: 1
        )
        let hit = ScreenGeometry.frontmostWindowID(
            at: CGPoint(x: 100, y: 100),
            orderedWindowIDs: [2, 1],
            candidates: [back, front]
        )
        #expect(hit == 2)
    }

    @Test func frontmostWindowIDSkipsWindowsNotUnderCursor() {
        let left = ScreenGeometry.WindowHitCandidate(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            windowLayer: 0,
            sourceIndex: 0
        )
        let right = ScreenGeometry.WindowHitCandidate(
            id: 20,
            frame: CGRect(x: 200, y: 0, width: 100, height: 100),
            windowLayer: 0,
            sourceIndex: 1
        )
        let hit = ScreenGeometry.frontmostWindowID(
            at: CGPoint(x: 250, y: 50),
            orderedWindowIDs: [10, 20],
            candidates: [left, right]
        )
        #expect(hit == 20)
    }

    @Test func frontmostWindowIDPrefersDisplaySizedFrontOverOccludedBack() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let finder = ScreenGeometry.WindowHitCandidate(
            id: 1,
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            windowLayer: 0,
            sourceIndex: 0
        )
        let cursor = ScreenGeometry.WindowHitCandidate(
            id: 2,
            frame: display,
            windowLayer: 0,
            sourceIndex: 1
        )
        let hit = ScreenGeometry.frontmostWindowID(
            at: CGPoint(x: 200, y: 200),
            orderedWindowIDs: [2, 1],
            candidates: [finder, cursor]
        )
        #expect(hit == 2)
    }

    @Test func pickableWindowTitleRequiresTitleOrAppName() {
        #expect(ScreenGeometry.isPickableWindowTitle("Finder"))
        #expect(ScreenGeometry.isPickableWindowTitle(nil, appName: "Cursor"))
        #expect(!ScreenGeometry.isPickableWindowTitle(""))
        #expect(!ScreenGeometry.isPickableWindowTitle("   ", appName: ""))
        #expect(!ScreenGeometry.isPickableWindowTitle(nil))
    }

    @Test func pickableWindowLayerAllowsNormalWindowsOnly() {
        #expect(ScreenGeometry.isPickableWindowLayer(0))
        #expect(!ScreenGeometry.isPickableWindowLayer(5))
        #expect(!ScreenGeometry.isPickableWindowLayer(-1))
    }
}

struct DisplaySelectionTests {
    @Test func screenFrameIndexFindsContainingDisplay() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        ]
        #expect(ScreenGeometry.screenFrameIndex(containing: CGPoint(x: 100, y: 100), in: frames) == 0)
        #expect(ScreenGeometry.screenFrameIndex(containing: CGPoint(x: 2000, y: 100), in: frames) == 1)
        #expect(ScreenGeometry.screenFrameIndex(containing: CGPoint(x: -50, y: 100), in: frames) == nil)
    }

    @Test func toolbarOriginValidation() {
        let frames = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let size = CGSize(width: 520, height: 72)
        #expect(ScreenGeometry.isValidToolbarOrigin(CGPoint(x: 100, y: 36), size: size, in: frames))
        #expect(!ScreenGeometry.isValidToolbarOrigin(CGPoint(x: 5000, y: 36), size: size, in: frames))
    }

    @Test func defaultToolbarOriginIsBottomCentered() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 520, height: 72)
        let origin = ScreenGeometry.defaultToolbarOrigin(on: screen, size: size)
        #expect(abs(origin.x - (1440 / 2 - 260)) < 0.001)
        #expect(abs(origin.y - 36) < 0.001)
    }
}

struct AspectRatioGlyphGeometryTests {
    @Test func sixteenByNineGlyphIsWiderThanTall() {
        let rect = AspectRatioGlyph.glyphRect(
            for: .sixteenToNine,
            in: CGSize(width: 18, height: 18)
        )
        #expect(rect.width > rect.height)
        #expect(abs((rect.width / rect.height) - (16.0 / 9.0)) < 0.05)
    }

    @Test func nineBySixteenGlyphIsTallerThanWide() {
        let rect = AspectRatioGlyph.glyphRect(
            for: .nineToSixteen,
            in: CGSize(width: 18, height: 18)
        )
        #expect(rect.height > rect.width)
        #expect(abs((rect.width / rect.height) - (9.0 / 16.0)) < 0.05)
    }

    @Test func oneToOneGlyphIsSquare() {
        let rect = AspectRatioGlyph.glyphRect(
            for: .oneToOne,
            in: CGSize(width: 18, height: 18)
        )
        #expect(abs(rect.width - rect.height) < 0.01)
    }
}

struct AspectLockedClampTests {
    @Test func clampAspectLockedPreservesSixteenByNine() {
        let screens = [CGRect(x: 0, y: 0, width: 800, height: 600)]
        let oversized = CGRect(x: -50, y: -50, width: 900, height: 900)
        let clamped = ScreenGeometry.clampAspectLockedRect(
            oversized,
            ratio: 16.0 / 9.0,
            toScreens: screens
        )
        #expect(clamped.width <= 800 + 0.01)
        #expect(clamped.height <= 600 + 0.01)
        #expect(abs((clamped.width / clamped.height) - (16.0 / 9.0)) < 0.02)
        #expect(screens[0].contains(CGPoint(x: clamped.midX, y: clamped.midY)))
    }

    @Test func clampAspectLockedFitsNearEdge() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800)]
        let nearEdge = CGRect(x: 900, y: 700, width: 320, height: 180)
        let clamped = ScreenGeometry.clampAspectLockedRect(
            nearEdge,
            ratio: 16.0 / 9.0,
            toScreens: screens
        )
        #expect(abs((clamped.width / clamped.height) - (16.0 / 9.0)) < 0.02)
        #expect(clamped.maxX <= 1000 + 0.01)
        #expect(clamped.maxY <= 800 + 0.01)
    }
}

@MainActor
struct GalleryFilterSelectionTests {
    @Test func pruneSelectionDropsHiddenAspectRatios() {
        let state = AppState.shared
        let previousFilter = state.aspectRatioFilter
        let previousSelection = state.selectedScreenshotIDs
        let previousLast = state.lastSelectedScreenshotID
        defer {
            state.aspectRatioFilter = previousFilter
            state.selectedScreenshotIDs = previousSelection
            state.lastSelectedScreenshotID = previousLast
        }

        let visible = CapturedScreenshot(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/a.png"),
            createdAt: Date(),
            aspectRatioRaw: AspectRatioOption.oneToOne.rawValue
        )
        let hidden = CapturedScreenshot(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/b.png"),
            createdAt: Date(),
            aspectRatioRaw: AspectRatioOption.sixteenToNine.rawValue
        )
        state.screenshots = [visible, hidden]
        state.selectedScreenshotIDs = [visible.id, hidden.id]
        state.lastSelectedScreenshotID = hidden.id
        state.aspectRatioFilter = .oneToOne

        #expect(state.selectedScreenshotIDs == [visible.id])
        #expect(state.lastSelectedScreenshotID == visible.id)
    }
}
