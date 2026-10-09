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
    @State private var shape: [ShapePoint]?
    @State private var showShapeEditor = false
    @FocusState private var nameFocused: Bool

    private var isNew: Bool { part == nil }
    private var isValid: Bool {
        if let shape { return PartShape.isSimple(shape) && quantity > 0 }
        return length > 0 && width > 0 && quantity > 0
    }

    /// Blank size: the shape's bounding box when shaped, otherwise the typed size.
    private var blank: (length: Double, width: Double) {
        guard let shape else { return (length, width) }
        let b = PartShape.bounds(shape)
        return (b.width, b.height)
    }

    private var shapeBinding: Binding<[ShapePoint]> {
        Binding(
            get: { shape ?? PartShape.rectangle(length: max(length, 1), width: max(width, 1)) },
            set: { shape = $0 })
    }

    private var stock: StockSheet? {
        project.sortedStocks.first { $0.id == stockID } ?? project.sortedStocks.first
    }

    private var tooLarge: Bool {
        guard let stock else { return false }
        let l = stock.length - 2 * project.edgeTrim, w = stock.width - 2 * project.edgeTrim
        let (length, width) = blank
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
                if shape != nil {
                    LabeledContent("Length", value: "\(unit.format(blank.length)) \(unit.symbol)")
                    LabeledContent("Width", value: "\(unit.format(blank.width)) \(unit.symbol)")
                } else {
                    LengthField("Length", value: $length)
                    LengthField("Width", value: $width)
                }
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
                Button {
                    showShapeEditor = true
                } label: {
                    HStack(spacing: 12) {
                        ShapeThumbnail(points: shape ?? PartShape.rectangle(length: max(length, 1), width: max(width, 1)))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shape == nil ? "Rectangle" : "Custom Shape")
                                .foregroundStyle(.primary)
                            Text(shape == nil ? "Tap to add points and angles" : "\(shape!.count) points · cut from a rectangular blank")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .disabled(shape == nil && (length <= 0 || width <= 0))
                if shape != nil {
                    Button("Make Rectangular", systemImage: "rectangle", role: .destructive) {
                        let (l, w) = blank
                        length = l
                        width = w
                        shape = nil
                        formID = UUID()
                    }
                }
            } header: {
                Text("Shape")
            } footer: {
                if let shape, !PartShape.isSimple(shape) {
                    Text("The outline crosses itself. Fix it in the shape editor to save.")
                        .foregroundStyle(.red)
                } else if shape == nil && (length <= 0 || width <= 0) {
                    Text("Enter a length and width first.")
                }
            }

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
                        shape = nil
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
                        let copy = Part(name: "", length: 1, width: 1, order: nextOrder)
                        context.insert(copy)
                        copy.project = project
                        apply(to: copy)
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
        .navigationDestination(isPresented: $showShapeEditor) {
            ShapeEditorView(points: shapeBinding)
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
            shape = part.shape
            if LaunchOptions.isDemo && LaunchOptions.screen == "shape" && shape != nil {
                showShapeEditor = true
            }
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
        if let shape {
            // Store the outline starting at the origin, and keep length and width as its blank.
            let normalized = PartShape.normalized(shape)
            let b = PartShape.bounds(normalized)
            part.shape = PartShape.isRectangle(normalized) ? nil : normalized
            part.length = b.width
            part.width = b.height
        } else {
            part.shape = nil
            part.length = length
            part.width = width
        }
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
            let new = Part(name: "", length: max(length, 1), width: max(width, 1), order: nextOrder)
            context.insert(new)
            new.project = project
            apply(to: new)
        }
    }
}

/// A small preview of a part's outline.
struct ShapeThumbnail: View {
    let points: [ShapePoint]

    var body: some View {
        Canvas { context, size in
            let b = PartShape.bounds(points)
            guard b.width > 0, b.height > 0 else { return }
            let inset: CGFloat = 4
            let scale = min((size.width - 2 * inset) / b.width, (size.height - 2 * inset) / b.height)
            let ox = (size.width - b.width * scale) / 2 - b.minX * scale
            let oy = (size.height - b.height * scale) / 2 - b.minY * scale
            var path = Path()
            path.addLines(points.map { CGPoint(x: ox + $0.x * scale, y: oy + $0.y * scale) })
            path.closeSubpath()
            context.fill(path, with: .color(.accentColor.opacity(0.25)))
            context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
        }
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
