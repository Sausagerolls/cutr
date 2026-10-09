import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context
    @Environment(\.lengthUnit) private var unit
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Folder.name) private var folders: [Folder]

    @State private var result: OptimizationResult = .empty
    @State private var isOptimising = false
    @State private var editing: EditTarget?
    @State private var showLayout = false
    @State private var width: CGFloat = 0

    /// Side-by-side editor and layout only when there is room for both.
    private var isWide: Bool { sizeClass == .regular && width >= 820 }

    enum EditTarget: Identifiable {
        case newPart
        case part(Part)
        case newStock
        case stock(StockSheet)

        var id: String {
            switch self {
            case .newPart: "newPart"
            case .part(let p): "part-\(p.id)"
            case .newStock: "newStock"
            case .stock(let s): "stock-\(s.id)"
            }
        }
    }

    /// Changes whenever anything that affects the layout changes.
    private struct Signature: Hashable {
        var stocks: [OptimizerStock]
        var parts: [OptimizerPart]
        var settings: OptimizerSettings
    }

    private var signature: Signature {
        let input = project.optimizerInput()
        return Signature(stocks: input.stocks, parts: input.parts, settings: project.optimizerSettings)
    }

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: 0) {
                    editor
                        .frame(width: 400)
                    Divider()
                        .ignoresSafeArea()
                    LayoutView(project: project, result: result, isOptimising: isOptimising)
                }
            } else {
                editor
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle(project.name.isEmpty ? String(localized: "Untitled") : project.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showLayout) {
            LayoutView(project: project, result: result, isOptimising: isOptimising)
                .navigationTitle("Cutting Layout")
                .toolbar { exportMenu }
        }
        .toolbar {
            if isWide {
                exportMenu
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                switch target {
                case .newPart: PartEditorView(project: project, part: nil)
                case .part(let part): PartEditorView(project: project, part: part)
                case .newStock: StockEditorView(project: project, stock: nil)
                case .stock(let stock): StockEditorView(project: project, stock: stock)
                }
            }
            .environment(\.lengthUnit, unit)
        }
        .task(id: signature) {
            await optimise()
        }
        .onAppear {
            if LaunchOptions.isDemo {
                switch LaunchOptions.screen {
                case "layout": showLayout = true
                case "part": editing = project.sortedParts.first.map { .part($0) }
                default: break
                }
            }
        }
    }

    private func optimise() async {
        let input = project.optimizerInput()
        let settings = project.optimizerSettings
        isOptimising = true
        // Debounce rapid edits such as typing a dimension.
        try? await Task.sleep(for: .milliseconds(result == .empty ? 0 : 150))
        guard !Task.isCancelled else { return }
        // A detached task does not inherit cancellation, so forward it. Otherwise
        // every keystroke would leave a stale optimisation running in the background.
        let work = Task.detached(priority: .userInitiated) {
            CutOptimizer.optimize(stocks: input.stocks, parts: input.parts, settings: settings)
        }
        let output = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        guard !Task.isCancelled else { return }
        result = output
        isOptimising = false
    }

    @ToolbarContentBuilder
    private var exportMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu("Export", systemImage: "square.and.arrow.up") {
                let report = CutSheetReport(project: project, result: result, unit: unit)
                ShareLink(item: CutSheetPDF(report: report),
                          preview: SharePreview(report.fileName, image: Image(systemName: "doc.richtext"))) {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
                Button("Print", systemImage: "printer") {
                    PrintService.print(CutSheetPDF(report: report))
                }
            }
            .disabled(result.sheets.isEmpty)
        }
    }

    // MARK: Editor

    private var editor: some View {
        Form {
            Section {
                TextField("Name", text: $project.name)
                    .font(.headline)
                TextField("Notes", text: $project.notes, axis: .vertical)
                    .lineLimit(1...4)
                if !folders.isEmpty {
                    Picker(selection: $project.folder) {
                        Text("None").tag(Folder?.none)
                        ForEach(folders) { folder in
                            Text(folder.name).tag(Optional(folder))
                        }
                    } label: {
                        Label("Project", systemImage: "folder")
                    }
                }
            }

            Section {
                LengthField("Kerf / buffer", value: $project.kerf)
                LengthField("Edge trim", value: $project.edgeTrim)
            } header: {
                Text("Cutting")
            } footer: {
                Text("Kerf is the gap left between parts for the saw blade plus any extra clearance. Edge trim is removed from every side of each sheet to clean up factory edges.")
            }

            Section {
                ForEach(project.sortedStocks) { stock in
                    Button {
                        editing = .stock(stock)
                    } label: {
                        StockRow(stock: stock, usage: result.usage.first { $0.stock.id == stock.id })
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    let stocks = project.sortedStocks
                    for i in offsets { context.delete(stocks[i]) }
                    project.touch()
                }
                Button("Add Sheet", systemImage: "plus.rectangle") { editing = .newStock }
            } header: {
                Text("Sheet Stock")
            }

            Section {
                ForEach(Array(project.sortedParts.enumerated()), id: \.element.id) { index, part in
                    Button {
                        editing = .part(part)
                    } label: {
                        PartRow(part: part, index: index, stockName: stockName(for: part))
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    let parts = project.sortedParts
                    for i in offsets { context.delete(parts[i]) }
                    project.touch()
                }
                .onMove { source, destination in
                    var parts = project.sortedParts
                    parts.move(fromOffsets: source, toOffset: destination)
                    for (i, part) in parts.enumerated() { part.order = i }
                    project.touch()
                }
                Button("Add Part", systemImage: "plus.square") { editing = .newPart }
                    .disabled(project.sortedStocks.isEmpty)
            } header: {
                HStack {
                    Text("Parts")
                    Spacer()
                    if project.totalPartCount > 0 {
                        Text("\(project.totalPartCount) total")
                    }
                }
            } footer: {
                if project.sortedStocks.isEmpty {
                    Text("Add a sheet before adding parts.")
                }
            }

            if !isWide {
                Section {
                    Button {
                        showLayout = true
                    } label: {
                        ResultSummary(result: result, isOptimising: isOptimising)
                    }
                    .tint(.primary)
                    .disabled(result.sheets.isEmpty)
                } header: {
                    Text("Layout")
                }
            }
        }
        .onChange(of: project.name) { project.touch() }
        .onChange(of: project.notes) { project.touch() }
        .onChange(of: project.folder) { project.touch() }
        .onChange(of: project.kerf) { project.touch() }
        .onChange(of: project.edgeTrim) { project.touch() }
    }

    private func stockName(for part: Part) -> String? {
        let stocks = project.sortedStocks
        guard stocks.count > 1 else { return nil }
        return (stocks.first { $0.id == part.stockID } ?? stocks.first)?.name
    }
}

private struct StockRow: View {
    let stock: StockSheet
    let usage: StockUsage?
    @Environment(\.lengthUnit) private var unit

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stock.name.isEmpty ? String(localized: "Sheet") : stock.name)
                Text("\(unit.format(stock.length)) × \(unit.format(stock.width)) × \(unit.format(stock.thickness)) \(unit.symbol)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let usage {
                    Text("\(usage.sheetsUsed) needed")
                        .font(.subheadline.weight(.semibold))
                }
                Text(stock.quantity > 0 ? String(localized: "\(stock.quantity) in stock") : String(localized: "Unlimited"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PartRow: View {
    let part: Part
    let index: Int
    let stockName: String?
    @Environment(\.lengthUnit) private var unit

    var body: some View {
        HStack(spacing: 12) {
            Text(Project.autoLabel(index))
                .font(.caption.weight(.bold))
                .frame(minWidth: 28, minHeight: 28)
                .background(Color(uiColor: SheetDrawing.color(index)).opacity(0.85), in: .rect(cornerRadius: 7))
                .foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(part.name.isEmpty ? String(localized: "Part") : part.name)
                    if part.grainLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Grain locked")
                    }
                }
                Text("\(unit.format(part.length)) × \(unit.format(part.width)) \(unit.symbol)\(stockName.map { " · \($0)" } ?? "")")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("×\(part.quantity)")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct ResultSummary: View {
    let result: OptimizationResult
    let isOptimising: Bool

    var body: some View {
        HStack {
            if result.sheets.isEmpty {
                Text(isOptimising ? "Optimising…" : "Add parts to see the layout")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("View Cutting Layout")
                        .font(.headline)
                    HStack(spacing: 10) {
                        Label("\(result.sheets.count)", systemImage: "rectangle.stack")
                        Label(result.utilisation.formatted(.percent.precision(.fractionLength(0))), systemImage: "chart.pie")
                        if result.totalCost > 0 {
                            Label(result.totalCost.formatted(.currency(code: Currency.code)), systemImage: "sterlingsign.circle")
                                .labelStyle(.titleOnly)
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    if result.unplacedCount > 0 {
                        Label("\(result.unplacedCount) parts don't fit", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            if isOptimising {
                ProgressView()
            } else if !result.sheets.isEmpty {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
