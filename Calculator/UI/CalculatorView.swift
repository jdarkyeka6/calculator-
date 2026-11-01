import SwiftUI

struct CalculatorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var display = "0"
    @State private var previous: Double?
    @State private var operation: String?
    @State private var nextStartsFresh = false

    private let rows: [[String]] = [
        ["AC", "+/-", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", ".", "⌫", "="]
    ]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 14) {
                Spacer()
                Text(display)
                    .font(.system(size: 60, weight: .light, design: .rounded))
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 20)
                    .accessibilityLabel("Display \(display)")
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { symbol in
                            Button { press(symbol) } label: {
                                Text(symbol)
                                    .font(.system(size: 28, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: min(geometry.size.width / 5, 82))
                                    .background(background(for: symbol), in: RoundedRectangle(cornerRadius: 26))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 18)
        }
    }

    private func background(for key: String) -> Color {
        if ["÷", "×", "−", "+", "="].contains(key) { return .orange }
        if ["AC", "+/-", "%"].contains(key) { return Color.white.opacity(0.34) }
        return Color.white.opacity(0.13)
    }

    private func press(_ key: String) {
        if key.count == 1, let character = key.first, character.isNumber {
            if nextStartsFresh || display == "0" || display == "Error" {
                display = key
                nextStartsFresh = false
            } else if display.count < 18 {
                display += key
            }
            return
        }
        switch key {
        case "AC":
            display = "0"; previous = nil; operation = nil; nextStartsFresh = false
        case "⌫":
            display = display.count > 1 ? String(display.dropLast()) : "0"
        case ".":
            if nextStartsFresh { display = "0"; nextStartsFresh = false }
            if !display.contains(".") { display += "." }
        case "+/-":
            if let number = Double(display) { display = formatted(-number) }
        case "%":
            if let number = Double(display) { display = formatted(number / 100) }
        case "+", "−", "×", "÷":
            previous = Double(display); operation = key; nextStartsFresh = true
        case "=":
            if operation == nil, display.allSatisfy(\.isNumber),
               model.calculatorEntered(display) {
                display = "0"; return
            }
            guard let old = previous, let current = Double(display), let op = operation else { return }
            let value: Double
            switch op {
            case "+": value = old + current
            case "−": value = old - current
            case "×": value = old * current
            default: value = current == 0 ? .nan : old / current
            }
            display = value.isFinite ? formatted(value) : "Error"
            previous = nil; operation = nil; nextStartsFresh = true
        default: break
        }
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e16 { return String(format: "%.0f", value) }
        return String(format: "%.9g", value)
    }
}
