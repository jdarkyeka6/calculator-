import SwiftUI

/// A 3×3 drag-only pattern. Nodes are numbered from 1 (top-left) to 9 (bottom-right).
struct PatternPad: View {
    let onComplete: (String) -> Void
    @State private var selected: [Int] = []

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Path { path in
                    for (index, node) in selected.enumerated() {
                        let point = position(for: node, side: side)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(.cyan, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

                ForEach(1...9, id: \.self) { node in
                    Circle()
                        .fill(selected.contains(node) ? Color.cyan : Color.white.opacity(0.12))
                        .overlay {
                            Circle().stroke(.white.opacity(0.5), lineWidth: 1.5)
                        }
                        .frame(width: 27, height: 27)
                        .position(position(for: node, side: side))
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let x = gesture.location.x
                        let y = gesture.location.y
                        guard x >= 0, y >= 0, x < side, y < side else { return }
                        let col = min(2, Int(x / (side / 3)))
                        let row = min(2, Int(y / (side / 3)))
                        let node = row * 3 + col + 1
                        if !selected.contains(node) { selected.append(node) }
                    }
                    .onEnded { _ in
                        let result = selected.map(String.init).joined()
                        selected = []
                        if result.count >= 4 { onComplete(result) }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Draw your secret pattern across at least four dots")
    }

    private func position(for node: Int, side: CGFloat) -> CGPoint {
        let column = CGFloat((node - 1) % 3)
        let row = CGFloat((node - 1) / 3)
        let step = side / 3
        return CGPoint(x: (column + 0.5) * step, y: (row + 0.5) * step)
    }
}
