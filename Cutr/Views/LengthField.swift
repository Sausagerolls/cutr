import SwiftUI

/// A text field for a length stored in millimetres, shown and typed in the user's unit.
struct LengthField: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    @Environment(\.lengthUnit) private var unit
    @State private var text = ""
    @FocusState private var focused: Bool

    init(_ title: LocalizedStringKey, value: Binding<Double>) {
        self.title = title
        self._value = value
    }

    /// Zero shows as an empty field so the placeholder prompts for input.
    private var display: String { value == 0 ? "" : unit.format(value) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField(title, text: $text, prompt: Text("0"))
                    .keyboardType(unit == .inches ? .numbersAndPunctuation : .decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focused)
                    .accessibilityLabel(Text(title))
                    .foregroundStyle(unit.parse(text) == nil && !text.isEmpty ? .red : .primary)
                Text(unit.symbol)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, alignment: .leading)
            }
        } label: {
            Text(title)
        }
        .onAppear { text = display }
        .onChange(of: unit) { text = display }
        .onChange(of: text) {
            if text.isEmpty {
                value = 0
            } else if let parsed = unit.parse(text), abs(parsed - value) > 1e-9 {
                value = parsed
            }
        }
        .onChange(of: focused) {
            if !focused { text = display }
        }
    }
}
