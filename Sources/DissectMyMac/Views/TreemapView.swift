import AppKit
import DissectCore
import SwiftUI

/// Two-level squarified treemap: each child of `node` is a tile, and folder tiles show their own
/// children as nested tiles so structure is visible at a glance.
struct TreemapView: View {
    let node: FileNode
    @Binding var hovered: FileNode?
    var onOpen: (FileNode) -> Void
    var onCollect: (FileNode) -> Void

    @Environment(\.appTheme) private var theme
    private let maxTiles = 400
    private let headerHeight: CGFloat = 18

    private struct Tile {
        let node: FileNode
        let rect: CGRect
        let color: Color
        let isNested: Bool
    }

    var body: some View {
        GeometryReader { geo in
            let tiles = layout(in: CGRect(origin: .zero, size: geo.size))
            Canvas { context, _ in
                for tile in tiles {
                    let rect = tile.rect.insetBy(dx: tile.isNested ? 0.5 : 1, dy: tile.isNested ? 0.5 : 1)
                    guard rect.width >= 1, rect.height >= 1 else { continue }
                    let isHovered = hovered == tile.node
                    let path = Path(roundedRect: rect, cornerRadius: tile.isNested ? 2 : 4)
                    context.fill(path, with: .color(tile.color.opacity(isHovered ? 1 : (tile.isNested ? 0.75 : 0.9))))
                    if isHovered {
                        context.stroke(path, with: .color(.white), lineWidth: 2)
                    } else if tile.isNested {
                        context.stroke(path, with: .color(.black.opacity(0.18)), lineWidth: 1)
                    }
                    if !tile.isNested, rect.width > 50, rect.height > 16 {
                        let label = Text("\(tile.node.name)  \(ByteFormat.string(tile.node.size))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                        context.draw(label, in: CGRect(x: rect.minX + 5, y: rect.minY + 2, width: rect.width - 10, height: headerHeight - 2))
                    } else if tile.isNested, rect.width > 70, rect.height > 30 {
                        let label = Text(tile.node.name).font(.system(size: 10)).foregroundColor(.white.opacity(0.9))
                        context.draw(label, in: rect.insetBy(dx: 4, dy: 3))
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hovered = hit(point, in: tiles)
                case .ended:
                    hovered = nil
                }
            }
            .onTapGesture { point in
                guard let tile = topLevelTile(at: point, in: tiles) else { return }
                onOpen(tile)
            }
            .contextMenu {
                if let hovered {
                    Button("Add “\(hovered.name)” to Collector") { onCollect(hovered) }
                    Button("Reveal in Finder") { FinderActions.reveal([hovered.url]) }
                    if hovered.isDirectory { Button("Open") { onOpen(hovered) } }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4)))
    }

    private func layout(in bounds: CGRect) -> [Tile] {
        let children = Array(node.children.prefix(maxTiles))
        guard !children.isEmpty else {
            return [Tile(node: node, rect: bounds, color: color(for: node, index: 0), isNested: false)]
        }
        let rects = Treemap.layout(children.map { Double(max(0, $0.size)) }, in: bounds)
        var tiles: [Tile] = []
        for (index, (child, rect)) in zip(children, rects).enumerated() {
            let color = color(for: child, index: index)
            tiles.append(Tile(node: child, rect: rect, color: color, isNested: false))
            // Nested tiles for folders big enough to show structure.
            if child.isDirectory, !child.children.isEmpty, rect.width > 60, rect.height > 50 {
                let inner = CGRect(x: rect.minX + 3, y: rect.minY + headerHeight,
                                   width: rect.width - 6, height: rect.height - headerHeight - 3)
                let grandchildren = Array(child.children.prefix(60))
                let innerRects = Treemap.layout(grandchildren.map { Double(max(0, $0.size)) }, in: inner)
                for (grandchild, innerRect) in zip(grandchildren, innerRects) {
                    let shade = grandchild.isDirectory ? color.opacity(0.85) : theme.color(for: FileCategory(extension: grandchild.fileExtension))
                    tiles.append(Tile(node: grandchild, rect: innerRect, color: shade, isNested: true))
                }
            }
        }
        return tiles
    }

    private func color(for node: FileNode, index: Int) -> Color {
        if node.isDirectory {
            let palette = theme.palette
            return palette[index % palette.count]
        }
        return theme.color(for: FileCategory(extension: node.fileExtension))
    }

    /// Deepest tile under the point (nested tiles are appended after their parent).
    private func hit(_ point: CGPoint, in tiles: [Tile]) -> FileNode? {
        tiles.last { $0.rect.contains(point) }?.node
    }

    private func topLevelTile(at point: CGPoint, in tiles: [Tile]) -> FileNode? {
        guard let deepest = tiles.last(where: { $0.rect.contains(point) }) else { return nil }
        if deepest.isNested {
            // Clicking inside a folder's nested area opens that nested folder directly if it is one.
            if deepest.node.isDirectory { return deepest.node }
            return deepest.node.parent
        }
        return deepest.node
    }
}
