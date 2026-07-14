import CoreGraphics
import Testing
@testable import scratio

struct scratioTests {

    @Test func aspectRatioOneToOneIsLocked() {
        #expect(AspectRatioOption.oneToOne.isLocked)
        #expect(AspectRatioOption.oneToOne.ratio == 1)
    }

    @Test func independentAspectRatioIsFreeform() {
        #expect(AspectRatioOption.independent.isLocked == false)
        #expect(AspectRatioOption.independent.ratio == nil)
    }

    @Test func constrainKeepsSixteenByNine() {
        let rect = CGRect(x: 0, y: 0, width: 320, height: 320)
        let constrained = CaptureSessionState.constrain(rect, to: .sixteenToNine)
        let ratio = constrained.width / constrained.height
        #expect(abs(ratio - (16.0 / 9.0)) < 0.01)
    }

    @Test func primaryScreenMaxYIsPositive() {
        #expect(ScreenshotCaptureService.primaryScreenMaxY() > 0)
    }

    @Test func convertToCaptureSpaceFlipsY() {
        let primaryMaxY = ScreenshotCaptureService.primaryScreenMaxY()
        let appKit = CGRect(x: 10, y: 20, width: 100, height: 50)
        let converted = ScreenshotCaptureService.convertToCaptureSpace(appKit)
        #expect(converted.origin.x == 10)
        #expect(converted.width == 100)
        #expect(converted.height == 50)
        #expect(abs(converted.origin.y - (primaryMaxY - 20 - 50)) < 0.001)
    }
}
