import CoreGraphics
import Testing

@testable import Nudge

@Suite("Geometry")
struct GeometryTests {
    let window = CGRect(x: 100, y: 50, width: 800, height: 600)

    @Test("A screen rect survives a round trip through window fractions")
    func roundTrip() {
        let rect = CGRect(x: 300, y: 200, width: 120, height: 40)
        let unit = UnitRect(rect, in: window)
        #expect(unit.x == 0.25)
        #expect(unit.y == 0.25)
        #expect(unit.screenRect(in: window) == rect)
    }

    @Test("Fractions follow the window when it moves")
    func followsWindow() {
        let unit = UnitRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1)
        let moved = window.offsetBy(dx: 40, dy: -20)
        #expect(unit.screenRect(in: moved) == unit.screenRect(in: window).offsetBy(dx: 40, dy: -20))
    }

    @Test("A null rect has no area")
    func nullArea() {
        #expect(CGRect.null.area == 0)
        #expect(CGRect(x: 0, y: 0, width: 4, height: 5).area == 20)
    }
}
