import CoreGraphics
import Foundation

/// Squarified treemap layout (Bruls, Huizing & van Wijk, 2000).
public enum Treemap {
    /// Returns one rectangle per value, in the same order as `values`.
    /// Zero or negative values get `.zero`. The rectangles tile `bounds` exactly.
    public static func layout(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let total = values.filter { $0 > 0 }.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }

        let scale = Double(bounds.width * bounds.height) / total
        let order = values.indices.filter { values[$0] > 0 }.sorted { values[$0] > values[$1] }

        func worstRatio(_ row: [Int], side: Double) -> Double {
            guard !row.isEmpty, side > 0 else { return .infinity }
            let areas = row.map { values[$0] * scale }
            let sum = areas.reduce(0, +)
            guard let maxArea = areas.max(), let minArea = areas.min(), sum > 0, minArea > 0 else { return .infinity }
            let side2 = side * side
            let sum2 = sum * sum
            return max(side2 * maxArea / sum2, sum2 / (side2 * minArea))
        }

        func place(_ row: [Int], in rect: CGRect) -> CGRect {
            let areas = row.map { values[$0] * scale }
            let sum = areas.reduce(0, +)
            if rect.width >= rect.height {
                // Column on the left edge.
                let width = rect.height > 0 ? CGFloat(sum) / rect.height : 0
                var y = rect.minY
                for (index, area) in zip(row, areas) {
                    let height = width > 0 ? CGFloat(area) / width : 0
                    result[index] = CGRect(x: rect.minX, y: y, width: width, height: height)
                    y += height
                }
                return CGRect(x: rect.minX + width, y: rect.minY, width: max(0, rect.width - width), height: rect.height)
            } else {
                // Row along the top edge.
                let height = rect.width > 0 ? CGFloat(sum) / rect.width : 0
                var x = rect.minX
                for (index, area) in zip(row, areas) {
                    let width = height > 0 ? CGFloat(area) / height : 0
                    result[index] = CGRect(x: x, y: rect.minY, width: width, height: height)
                    x += width
                }
                return CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: max(0, rect.height - height))
            }
        }

        var remaining = bounds
        var row: [Int] = []
        var i = 0
        while i < order.count {
            let candidate = order[i]
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worstRatio(row + [candidate], side: side) <= worstRatio(row, side: side) {
                row.append(candidate)
                i += 1
            } else {
                remaining = place(row, in: remaining)
                row.removeAll()
            }
        }
        if !row.isEmpty { _ = place(row, in: remaining) }
        return result
    }
}
