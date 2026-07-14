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

    @Test func defaultSortOrderIsNewestFirst() {
        #expect(GallerySortOrder.newestFirst.title == "Newest First")
    }
}
