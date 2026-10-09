import SwiftUI
import SwiftData

struct PartEditorView: View {
    let project: Project
    let part: Part?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lengthUnit) private var unit

    @State private var name = ""
    @State private var length = 0.0
    @State private var width = 0.0
    @State private var quantity = 1
    @State private var grainLocked = false
    @State private var stockID: UUID?
    @State private var addedCount = 0
    @State private var formID = UUID()
    @FocusState private var nameFocused: Bool

    private var isNew: Bool { part == nil }
    private var isValid: Bool { length > 0 && width > 0 && quantity > 0 }

    private var stock: StockSheet? {
        project.sortedStocks.first { $0.id == stockID } ?? project.sortedStocks.first
    }

    private var tooLarge: Bool {
        guard let stock else { return false }
        let l = stock.length - 2 * project.edgeTrim, w = stock.width - 2 * project.edgeTrim
        let fits = length <= l && width <= w
        let fitsRotated = !grainLocked && width <= l && length <= w
        return !(fits || fitsRotated)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name (optional)", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.next)
                LengthField("Length", value: $length)
                LengthField("Width", value: $width)
                Stepper(value: $quantity, in: 1...999) {
                    LabeledContent("Quantity") {
                        TextField("Quantity", value: $quantity, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 80)
                    }
                }
            } footer: {
                if tooLarge {
                    Label("This part is larger than the usable area of the sheet.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .id(formID)

            Section {
                Toggle(isOn: $grainLocked) {
                    Label("Lock grain direction", systemImage: "lines.measurement.horizontal")
                }
                if project.sortedStocks.count > 1 {
                    Picker("Material", selection: $stockID) {
                        ForEach(project.sortedStocks) { stock in
                            Text(stock.name).tag(Optional(stock.id))
                        }
                    }
                }
            } footer: {
                Text("Locked parts keep their length running along the sheet's length, so the grain matches. Unlocked parts may be rotated to save material.")
            }

            if isNew {
                Section {
                    Button {
                        save()
                        addedCount += 1
                        name = ""
                        length = 0
                        width = 0
                        quantity = 1
                        formID = UUID()
                        nameFocused = true
                    } label: {
                        Label("Save and Add Another", systemImage: "plus.circle")
                    }
                    .disabled(!isValid)
                } footer: {
                    if addedCount > 0 {
                        Text("\(addedCount) added")
                    }
                }
            } else if let part {
                Section {
                    Button("Duplicate Part", systemImage: "plus.square.on.square") {
                        let copy = Part(name: name, length: length, width: width, quantity: quantity,
                                        grainLocked: grainLocked, stockID: stockID, order: nextOrder)
                        context.insert(copy)
                        copy.project = project
                        apply(to: part)
                        dismiss()
                    }
                    Button("Delete Part", systemImage: "trash", role: .destructive) {
                        context.delete(part)
                        project.touch()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New Part" : "Edit Part")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(addedCount > 0 ? "Done" : "Cancel", role: .cancel) { dismiss() }
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

    private var nextOrder: Int {
        (project.parts ?? []).map(\.order).max().map { $0 + 1 } ?? 0
    }

    private func load() {
        if let part {
            name = part.name
            length = part.length
            width = part.width
            quantity = part.quantity
            grainLocked = part.grainLocked
            stockID = part.stockID ?? project.sortedStocks.first?.id
        } else {
            stockID = project.sortedStocks.first?.id
            if let last = project.sortedParts.last {
                stockID = last.stockID ?? stockID
            }
            nameFocused = true
        }
    }

    private func apply(to part: Part) {
        part.name = name.trimmingCharacters(in: .whitespaces)
        part.length = length
        part.width = width
        part.quantity = quantity
        part.grainLocked = grainLocked
        part.stockID = stockID
        project.touch()
    }

    private func save() {
        guard isValid else { return }
        if let part {
            apply(to: part)
        } else {
            let new = Part(name: "", length: length, width: width, order: nextOrder)
            context.insert(new)
            new.project = project
            apply(to: new)
        }
    }
}
