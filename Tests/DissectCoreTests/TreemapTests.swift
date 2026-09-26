@testable import DissectCore
import CoreGraphics
import XCTest

final class TreemapTests: XCTestCase {
    func testAreasAreProportionalAndTileTheBounds() {
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let rects = Treemap.layout(values, in: bounds)
        XCTAssertEqual(rects.count, values.count)

        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            let expected = Double(bounds.width * bounds.height) * value / total
            XCTAssertEqual(Double(rect.width * rect.height), expected, accuracy: 0.5)
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect), "\(rect) escapes bounds")
        }
        // No overlaps.
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                XCTAssertLessThan(overlap.isNull ? 0 : overlap.width * overlap.height, 0.5)
            }
        }
    }

    func testPreservesInputOrderAndHandlesZeros() {
        let rects = Treemap.layout([1, 0, 3], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(rects[1], .zero)
        XCTAssertGreaterThan(rects[2].width * rects[2].height, rects[0].width * rects[0].height)
    }

    func testEmptyInputs() {
        XCTAssertEqual(Treemap.layout([], in: CGRect(x: 0, y: 0, width: 10, height: 10)), [])
        XCTAssertEqual(Treemap.layout([1, 2], in: .zero), [.zero, .zero])
    }

    func testRectanglesAreReasonablySquare() {
        let values = (1...50).map { Double($0) }
        let rects = Treemap.layout(values, in: CGRect(x: 0, y: 0, width: 800, height: 500))
        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
        XCTAssertLessThan(worst, 8)
    }
}
