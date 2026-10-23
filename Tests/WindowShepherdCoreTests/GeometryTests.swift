import XCTest
@testable import WindowShepherdCore

func screen(_ id: UInt32, _ name: String, x: CGFloat, w: CGFloat = 1000, h: CGFloat = 800,
            builtin: Bool = false, uuid: String? = nil) -> ScreenInfo {
    let full = CGRect(x: x, y: 0, width: w, height: h)
    return ScreenInfo(displayID: id, uuid: uuid ?? "UUID-\(id)", name: name, isBuiltin: builtin,
                      frame: CGRect(x: x, y: 25, width: w, height: h - 25), full: full)
}

final class GeometryTests: XCTestCase {
    func testPlaceAndUnitRoundTrip() {
        let f = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let u = UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9)
        let r = Geometry.place(u, in: f)
        XCTAssertEqual(r, CGRect(x: 150, y: 90, width: 900, height: 720))
        let back = Geometry.unit(of: r, in: f)
        XCTAssertEqual(back.x, 0.05, accuracy: 1e-9)
        XCTAssertEqual(back.h, 0.9, accuracy: 1e-9)
    }

    func testCenteredShrinksToFit() {
        let f = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(Geometry.centered(CGSize(width: 800, height: 600), in: f), f)
        XCTAssertEqual(Geometry.centered(CGSize(width: 200, height: 100), in: f), CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    func testFitInside() {
        let f = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(Geometry.fit(CGRect(x: 350, y: -20, width: 100, height: 100), inside: f),
                       CGRect(x: 300, y: 0, width: 100, height: 100))
        XCTAssertEqual(Geometry.fit(CGRect(x: 10, y: 10, width: 900, height: 100), inside: f),
                       CGRect(x: 0, y: 10, width: 400, height: 100))
    }

    func testFlip() {
        XCTAssertEqual(Geometry.flip(CGRect(x: 0, y: 0, width: 1440, height: 875), primaryHeight: 900),
                       CGRect(x: 0, y: 25, width: 1440, height: 875))
    }

    func testWhereIsUsesCenterInFull() {
        let a = screen(1, "A", x: 0), b = screen(2, "B", x: 1000)
        // mostly on A but centre on B? centre x = 900+300/2... use a window whose centre is on B
        let w = CGRect(x: 800, y: 100, width: 500, height: 400)   // centre x 1050 → B
        let spot = Geometry.whereIs(w, in: [a, b])
        XCTAssertEqual(spot?.scr, "UUID-2")
        XCTAssertEqual(spot!.unit.x, -0.2, accuracy: 1e-9)
        XCTAssertNil(Geometry.whereIs(CGRect(x: 5000, y: 0, width: 100, height: 100), in: [a, b]))
    }

    func testSameSpotTolerance() {
        let u = UnitRect(x: 0.1, y: 0.1, w: 0.5, h: 0.5)
        let a = Spot(scr: "A", unit: u)
        XCTAssertTrue(Geometry.sameSpot(a, Spot(scr: "A", unit: UnitRect(x: 0.104, y: 0.1, w: 0.5, h: 0.5))))
        XCTAssertFalse(Geometry.sameSpot(a, Spot(scr: "A", unit: UnitRect(x: 0.106, y: 0.1, w: 0.5, h: 0.5))))
        XCTAssertFalse(Geometry.sameSpot(a, Spot(scr: "B", unit: u)))
        XCTAssertFalse(Geometry.sameSpot(a, nil))
        XCTAssertFalse(Geometry.sameSpot(nil, nil))
    }

    func testScreenMostOf() {
        let a = screen(1, "A", x: 0), b = screen(2, "B", x: 1000)
        XCTAssertEqual(Geometry.screen(mostOf: CGRect(x: 700, y: 0, width: 500, height: 100), in: [a, b])?.displayID, 1)
        XCTAssertEqual(Geometry.screen(mostOf: CGRect(x: 800, y: 0, width: 500, height: 100), in: [a, b])?.displayID, 2)
        XCTAssertNil(Geometry.screen(mostOf: CGRect(x: 5000, y: 0, width: 10, height: 10), in: [a, b]))
    }

    func testNextIsCyclic() {
        let a = screen(1, "A", x: 0), b = screen(2, "B", x: 1000), c = screen(3, "C", x: -1000)
        XCTAssertEqual(Screens.next(after: a, in: [a, b, c]), b)
        XCTAssertEqual(Screens.next(after: c, in: [a, b, c]), a)
        XCTAssertEqual(Screens.next(after: a, in: [a]), a)
    }

    func testPlacerOwnScreenFallsBackToMain() {
        let a = screen(1, "A", x: 0), b = screen(2, "B", x: 1000)
        let p = Placer.unit(UnitRect(x: 0, y: 0, w: 0.5, h: 1), .own)
        let off = CGRect(x: 9000, y: 9000, width: 100, height: 100)
        XCTAssertEqual(p.frame(for: off, screens: [a, b], main: b), CGRect(x: 1000, y: 25, width: 500, height: 775))
        let onA = CGRect(x: 10, y: 30, width: 100, height: 100)
        XCTAssertEqual(p.frame(for: onA, screens: [a, b], main: b), CGRect(x: 0, y: 25, width: 500, height: 775))
    }

    func testPlacerCenterKeepsSize() {
        let a = screen(1, "A", x: 0)
        let r = Placer.center(.own).frame(for: CGRect(x: 0, y: 30, width: 200, height: 175), screens: [a], main: a)
        XCTAssertEqual(r, CGRect(x: 400, y: 325, width: 200, height: 175))
    }

    func testPlacerGoneScreenIsNil() {
        let a = screen(1, "A", x: 0)
        XCTAssertNil(Placer.fraction(0.9, on: .fixed(uuid: "GONE")).frame(for: .zero, screens: [a], main: a))
    }

    func testPlacerFitInside() {
        let a = screen(1, "A", x: 0)
        let p = Placer.unit(UnitRect(x: 0.9, y: 0, w: 0.5, h: 0.5), .fixed(uuid: "UUID-1"), fitInside: true)
        let r = p.frame(for: .zero, screens: [a], main: a)!
        XCTAssertEqual(r.maxX, 1000)
    }

    func testDestinationsClamshellAndTwins() {
        // (a) clamshell: two identical monitors, numbered left to right, same names
        let d1 = screen(1, "DELL U2720Q", x: 2560, w: 2560), d2 = screen(2, "DELL U2720Q", x: 0, w: 2560)
        let a = Screens.destinations([d1, d2])
        XCTAssertEqual(a.map(\.num), [1, 2])
        XCTAssertEqual(a.map(\.screen.displayID), [2, 1])
        XCTAssertEqual(a.map(\.name), ["DELL U2720Q", "DELL U2720Q"])
        XCTAssertFalse(a[0].isLaptop)
        // (b) laptop is always 1, even when a monitor sits to its left
        let lap = screen(3, "Built-in Retina Display", x: 0, builtin: true), left = screen(4, "LG", x: -2560, w: 2560)
        let b = Screens.destinations([left, lap])
        XCTAssertEqual(b.map(\.name), ["Laptop", "LG"])
        XCTAssertTrue(b[0].isLaptop)
        // (c) empty name
        XCTAssertEqual(Screens.destinations([lap, screen(5, "", x: 1000)])[1].name, "Monitor")
        // (d) twins have distinct setup keys
        XCTAssertNotEqual(Screens.setupKey([lap, d1]), Screens.setupKey([lap, d2]))
        XCTAssertEqual(Screens.setupKey([d1, lap]), Screens.setupKey([lap, d1]))
    }

    func testSetupLabelAndDefaults() {
        let lap = screen(3, "Built-in", x: 0, builtin: true), m = screen(4, "", x: 1000)
        XCTAssertEqual(Screens.setupLabel([m, lap]), "? + Built-in")
        let d = Screens.destinations([lap, m])
        XCTAssertEqual(Screens.defaultFraction(d[0]), 1.0)
        XCTAssertEqual(Screens.defaultFraction(d[1]), 0.9)
        XCTAssertEqual(sizeLabel(1.0), "full")
        XCTAssertEqual(sizeLabel(0.9), "90%")
        XCTAssertEqual(sizeLabel(0.6), "60%")
    }

    func testActionPlacements() {
        XCTAssertEqual(ActionID.almost.placement, .unit(UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9)))
        XCTAssertEqual(ActionID.sixty.placement, .unit(UnitRect(x: 0.2, y: 0.2, w: 0.6, h: 0.6)))
        XCTAssertEqual(ActionID.bottomRight.placement, .unit(UnitRect(x: 0.5, y: 0.5, w: 0.5, h: 0.5)))
        XCTAssertEqual(ActionID.center.placement, .center)
    }
}
