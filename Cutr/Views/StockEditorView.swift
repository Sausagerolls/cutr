import SwiftUI
import SwiftData

struct StockEditorView: View {
    let project: Project
    let stock: StockSheet?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lengthUnit) private var unit

    @State private var name = ""
    @State private var length = 2440.0
    @State private var width = 1220.0
    @State private var thickness = 18.0
    @State private var limited = false
    @State private var quantity = 1
    @State private var price = 0.0
    @State private var formID = UUID()

    private var isNew: Bool { stock == nil }
    private var isValid: Bool { length > 0 && width > 0 && length > 2 * project.edgeTrim && width > 2 * project.edgeTrim }

    private struct Preset: Identifiable {
        var id: String { title }
        var title: String
        var length: Double
        var width: Double
    }

    private let presets = [
        Preset(title: "2440 × 1220 mm (8 × 4 ft)", length: 2440, width: 1220),
        Preset(title: "2500 × 1250 mm", length: 2500, width: 1250),
        Preset(title: "3050 × 1525 mm (10 × 5 ft)", length: 3050, width: 1525),
        Preset(title: "1220 × 607 mm (4 × 2 ft)", length: 1220, width: 607),
        Preset(title: "2440 × 607 mm (8 × 2 ft)", length: 2440, width: 607),
        Preset(title: "1525 × 1525 mm (Baltic birch)", length: 1525, width: 1525),
    ]

    var body: some View {
        Form {
            Section {
                TextField("Name, e.g. Birch Ply 18mm", text: $name)
                LengthField("Length", value: $length)
                LengthField("Width", value: $width)
                LengthField("Thickness", value: $thickness)
                Menu {
                    ForEach(presets) { preset in
                        Button(preset.title) {
                            length = preset.length
                            width = preset.width
                            formID = UUID()
                        }
                    }
                } label: {
                    Label("Common Sizes", systemImage: "list.bullet.rectangle")
                }
            } footer: {
                Text("Length runs along the grain.")
            }
            .id(formID)

            Section {
                Toggle("Limited quantity", isOn: $limited)
                if limited {
                    Stepper("\(quantity) available", value: $quantity, in: 1...999)
                }
                LabeledContent("Price per sheet") {
                    TextField("Price", value: $price, format: .currency(code: Currency.code))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Stock & Cost")
            } footer: {
                Text("Leave quantity unlimited to find out how many sheets to buy.")
            }

            if let stock, project.sortedStocks.count > 1 {
                Section {
                    Button("Delete Sheet", systemImage: "trash", role: .destructive) {
                        context.delete(stock)
                        project.touch()
                        dismiss()
                    }
                } footer: {
                    Text("Parts using this sheet will move to the first sheet.")
                }
            }
        }
        .navigationTitle(isNew ? "New Sheet" : "Edit Sheet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save") {
                    save()
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let stock else {
            let thicknessText = unit.format(thickness, includeSymbol: true)
            name = String(localized: "Sheet \(thicknessText)")
            return
        }
        name = stock.name
        length = stock.length
        width = stock.width
        thickness = stock.thickness
        limited = stock.quantity > 0
        quantity = max(stock.quantity, 1)
        price = stock.price
    }

    private func save() {
        let target: StockSheet
        if let stock {
            target = stock
        } else {
            let order = (project.stocks ?? []).map(\.order).max().map { $0 + 1 } ?? 0
            target = StockSheet(name: "", length: length, width: width, order: order)
            context.insert(target)
            target.project = project
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.length = length
        target.width = width
        target.thickness = thickness
        target.quantity = limited ? quantity : 0
        target.price = max(price, 0)
        project.touch()
    }
}
