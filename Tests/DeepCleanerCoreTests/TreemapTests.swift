import CoreGraphics
import Testing
@testable import DeepCleanerCore

@Suite struct TreemapTests {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    @Test func preservesAreaAndStaysInBounds() {
        let values: [Double] = [60, 60, 40, 30, 20, 20, 10, 6, 3, 1]
        let rects = Treemap.squarify(values, in: bounds)
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            let expected = value / total * Double(bounds.width * bounds.height)
            #expect(abs(Double(rect.width * rect.height) - expected) < 0.5)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
        }
    }

    @Test func rectsDoNotOverlap() {
        let rects = Treemap.squarify([50, 30, 20, 10, 5, 5, 2], in: bounds)
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func handlesEmptyAndZeroValues() {
        #expect(Treemap.squarify([], in: bounds).isEmpty)
        #expect(Treemap.squarify([0, 0], in: bounds) == [.zero, .zero])
        let rects = Treemap.squarify([10, 0], in: bounds)
        #expect(rects[1] == .zero)
        #expect(rects[0].width == bounds.width)
    }
}
