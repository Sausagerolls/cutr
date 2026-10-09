import SwiftUI

struct LayoutView: View {
    let project: Project
    let result: OptimizationResult
    let isOptimising: Bool
    @Environment(\.lengthUnit) private var unit

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if result.sheets.isEmpty && result.unplaced.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to Cut Yet", systemImage: "square.dashed")
                    } description: {
                        Text("Add parts to see the most efficient cutting layout.")
                    }
                    .padding(.top, 60)
                } else {
                    StatsCard(result: result)
                    if !result.unplaced.isEmpty {
                        UnplacedCard(unplaced: result.unplaced)
                    }
                    ForEach(Array(result.sheets.enumerated()), id: \.element.id) { index, sheet in
                        SheetCard(sheet: sheet, index: index, count: result.sheets.count, trim: project.edgeTrim)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            if isOptimising && !result.sheets.isEmpty {
                ProgressView()
                    .padding(8)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.top, 8)
            }
        }
    }
}

private struct StatsCard: View {
    let result: OptimizationResult
    @Environment(\.lengthUnit) private var unit

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Stat(title: "Sheets", value: "\(result.sheets.count)")
                Stat(title: "Parts", value: "\(result.placedCount)")
                Stat(title: "Yield", value: result.utilisation.formatted(.percent.precision(.fractionLength(0))))
                if result.totalCost > 0 {
                    Stat(title: "Cost", value: result.totalCost.formatted(.currency(code: Currency.code).precision(.fractionLength(0))))
                }
            }
            Gauge(value: result.utilisation) {
                EmptyView()
            }
            .gaugeStyle(.linearCapacity)
            .tint(Gradient(colors: [.orange, .green]))
            if result.usage.count > 1 || (result.usage.first?.stock.price ?? 0) > 0 {
                Divider()
                ForEach(result.usage) { usage in
                    HStack {
                        Text("\(usage.sheetsUsed) × \(usage.stock.name)")
                        Spacer()
                        if usage.stock.price > 0 {
                            Text(usage.cost.formatted(.currency(code: Currency.code)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            }
            Text("Kerf \(unit.format(result.settings.kerf, includeSymbol: true)) · Edge trim \(unit.format(result.settings.edgeTrim, includeSymbol: true))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private struct Stat: View {
        let title: LocalizedStringKey
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct UnplacedCard: View {
    let unplaced: [UnplacedPart]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Some parts could not be placed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(unplaced) { item in
                let reason = item.reason == .tooLarge
                    ? String(localized: "too large for the sheet")
                    : String(localized: "not enough sheets in stock")
                Text("\(item.count) × \(item.label) \(item.name) — \(reason)")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 16))
    }
}

private struct SheetCard: View {
    let sheet: SheetLayout
    let index: Int
    let count: Int
    let trim: Double
    @Environment(\.lengthUnit) private var unit
    @State private var selected: Placement?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sheet \(index + 1) of \(count)")
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize()
                Text(sheet.stock.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(sheet.utilisation.formatted(.percent.precision(.fractionLength(0)))) used")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            SheetDiagram(sheet: sheet, trim: trim, selected: $selected)
            Group {
                if let selected {
                    HStack {
                        Circle()
                            .fill(Color(uiColor: SheetDrawing.color(selected.colorIndex)))
                            .frame(width: 10, height: 10)
                        Text("\(selected.label) \(selected.name)").fontWeight(.semibold)
                        Text("\(unit.format(selected.length)) × \(unit.format(selected.width)) \(unit.symbol)")
                            .monospacedDigit()
                        if selected.rotated {
                            Label("Rotated", systemImage: "rotate.right")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("at \(unit.format(selected.x)), \(unit.format(selected.y))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(unit.format(sheet.stock.length)) × \(unit.format(sheet.stock.width)) \(unit.symbol) · Tap a part for details")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

struct SheetDiagram: View {
    let sheet: SheetLayout
    let trim: Double
    @Binding var selected: Placement?
    @Environment(\.lengthUnit) private var unit
    @Environment(\.colorScheme) private var colorScheme
    @State private var size: CGSize = .zero

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.withCGContext { cg in
                UIGraphicsPushContext(cg)
                SheetDrawing.draw(sheet, in: rect, unit: unit, trim: trim,
                                  style: .screen(dark: colorScheme == .dark), context: cg)
                UIGraphicsPopContext()
            }
            if let selected {
                let scale = min(size.width / sheet.stock.length, size.height / sheet.stock.width)
                let r = CGRect(x: selected.x * scale, y: selected.y * scale,
                               width: selected.length * scale, height: selected.width * scale)
                context.stroke(Path(r.insetBy(dx: 1, dy: 1)), with: .color(.accentColor), lineWidth: 3)
            }
        }
        .aspectRatio(SheetDrawing.aspect(sheet), contentMode: .fit)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .contentShape(.rect)
        .gesture(SpatialTapGesture().onEnded { value in
            selected = placement(at: value.location)
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sheet diagram with \(sheet.placements.count) parts"))
    }

    private func placement(at point: CGPoint) -> Placement? {
        // The canvas matches the sheet's aspect ratio, so one scale maps both axes.
        guard sheet.stock.length > 0, size.width > 0 else { return nil }
        let scale = min(size.width / sheet.stock.length, size.height / sheet.stock.width)
        let mm = CGPoint(x: point.x / scale, y: point.y / scale)
        let hit = sheet.placements.first { $0.rect.contains(mm) }
        return hit == selected ? nil : hit
    }
}
