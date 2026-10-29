import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing & van Wijk). Rows are laid along the shorter side of
/// the remaining rectangle, growing while the worst aspect ratio in the row keeps improving.
public enum Treemap {
    /// `values` should be sorted descending. Returns one rect per value; non-positive values get `.zero`.
    public static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let positive = values.prefix { $0 > 0 }.count
        let total = values.prefix(positive).reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }

        let scale = Double(rect.width * rect.height) / total
        let areas = values.prefix(positive).map { $0 * scale }
        var remaining = rect
        var start = 0

        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            guard side > 0 else { break }
            var end = start + 1
            var sum = areas[start], rowMax = areas[start], rowMin = areas[start]
            while end < areas.count {
                let next = areas[end]
                let current = worst(sum: sum, max: rowMax, min: rowMin, side: side)
                let candidate = worst(sum: sum + next, max: max(rowMax, next), min: min(rowMin, next), side: side)
                guard candidate <= current else { break }
                sum += next
                rowMax = max(rowMax, next)
                rowMin = min(rowMin, next)
                end += 1
            }

            let thickness = CGFloat(sum / side)
            var offset: CGFloat = 0
            if remaining.width >= remaining.height {
                for i in start..<end {
                    let length = CGFloat(areas[i]) / thickness
                    result[i] = CGRect(x: remaining.minX, y: remaining.minY + offset, width: thickness, height: length)
                    offset += length
                }
                remaining = CGRect(x: remaining.minX + thickness, y: remaining.minY,
                                   width: max(remaining.width - thickness, 0), height: remaining.height)
            } else {
                for i in start..<end {
                    let length = CGFloat(areas[i]) / thickness
                    result[i] = CGRect(x: remaining.minX + offset, y: remaining.minY, width: length, height: thickness)
                    offset += length
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + thickness,
                                   width: remaining.width, height: max(remaining.height - thickness, 0))
            }
            start = end
        }
        return result
    }

    static func worst(sum: Double, max: Double, min: Double, side: Double) -> Double {
        let side2 = side * side, sum2 = sum * sum
        return Swift.max(side2 * max / sum2, sum2 / (side2 * min))
    }
}
