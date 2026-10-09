import SwiftUI

/// Edits a part's outline. Points can be dragged, added on edges and deleted,
/// with snapping to a grid and to alignment guides from the other points.
/// Changes are made on a copy and only written back when the user taps Done.
struct ShapeEditorView: View {
    @Binding var shape: [ShapePoint]
    @Environment(\.lengthUnit) private var unit
    @Environment(\.dismiss) private var dismiss
    @State private var points: [ShapePoint] = []
    @State private var original: [ShapePoint] = []
    @State private var loaded = false

    enum Tool: String, CaseIterable, Identifiable {
        case move, add, delete
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .move: "Move"
            case .add: "Add Point"
            case .delete: "Delete"
            }
        }

        var systemImage: String {
            switch self {
            case .move: "hand.point.up.left"
            case .add: "plus.circle"
            case .delete: "minus.circle"
            }
        }
    }

    /// An alignment line shown while a point is snapped to it.
    private enum Guide: Hashable {
        case vertical(Double)
        case horizontal(Double)
    }

    @State private var tool: Tool = .move
    @State private var selected: Int?
    @State private var dragging: Int?
    @State private var grabOffset = CGSize.zero
    @State private var gestureActive = false
    @State private var guides: Set<Guide> = []
    @State private var undoStack: [[ShapePoint]] = []
    @State private var redoStack: [[ShapePoint]] = []
    @State private var viewport = CGRect.zero
    @State private var canvasSize = CGSize.zero
    @State private var snapFeedback = 0

    @AppStorage("shapeSnapGrid") private var snapGrid = true
    @AppStorage("shapeSnapAlign") private var snapAlign = true
    @AppStorage("shapeGridSize") private var gridSize = 10.0

    private let vertexHitRadius: CGFloat = 24
    private let edgeHitDistance: CGFloat = 24
    private let snapDistance: CGFloat = 12

    private var isValid: Bool { PartShape.isSimple(points) }
    private var bounds: CGRect { PartShape.bounds(points) }

    var body: some View {
        canvas
            .background(Color(.secondarySystemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
            .navigationTitle("Shape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sensoryFeedback(.selection, trigger: snapFeedback)
            .navigationBarBackButtonHidden()
            .interactiveDismissDisabled(points != original)
            .onAppear {
                if gridSize <= 0 { gridSize = unit == .inches ? 6.35 : 10 }
                if !loaded {
                    points = shape
                    original = shape
                    loaded = true
                }
                fitViewport()
            }
            .onChange(of: points) {
                if dragging == nil && !viewport.contains(bounds) { fitViewport() }
            }
    }

    // MARK: Canvas

    private var canvas: some View {
        Canvas { context, size in
            let t = transform(for: size)
            drawGrid(&context, size: size, t: t)
            drawBlank(&context, t: t)
            drawShape(&context, t: t)
            drawGuides(&context, size: size, t: t)
            drawVertices(&context, t: t)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .contentShape(.rect)
        .gesture(dragGesture)
        .accessibilityLabel(Text("Shape with \(points.count) points"))
    }

    private struct Transform {
        var scale: CGFloat
        var offset: CGPoint

        func screen(_ p: ShapePoint) -> CGPoint {
            CGPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale)
        }

        func model(_ p: CGPoint) -> ShapePoint {
            ShapePoint(x: (p.x - offset.x) / scale, y: (p.y - offset.y) / scale)
        }
    }

    private func transform(for size: CGSize) -> Transform {
        guard viewport.width > 0, viewport.height > 0, size.width > 0 else {
            return Transform(scale: 1, offset: .zero)
        }
        let scale = min(size.width / viewport.width, size.height / viewport.height)
        return Transform(scale: scale, offset: CGPoint(
            x: (size.width - viewport.width * scale) / 2 - viewport.minX * scale,
            y: (size.height - viewport.height * scale) / 2 - viewport.minY * scale))
    }

    private func fitViewport() {
        let b = bounds
        let pad = max(b.width, b.height) * 0.18 + 1
        viewport = b.insetBy(dx: -pad, dy: -pad)
    }

    private func drawGrid(_ context: inout GraphicsContext, size: CGSize, t: Transform) {
        guard gridSize > 0 else { return }
        // Thin out the grid so lines are never closer than 10 points.
        var step = gridSize
        while step * t.scale < 10 { step *= 5 }
        let topLeft = t.model(.zero), bottomRight = t.model(CGPoint(x: size.width, y: size.height))
        var minor = Path(), major = Path()
        var x = (topLeft.x / step).rounded(.down) * step
        while x <= bottomRight.x {
            let sx = t.screen(ShapePoint(x: x, y: 0)).x
            let isMajor = abs((x / (step * 5)).rounded() * step * 5 - x) < 1e-6
            let line = Path { $0.move(to: CGPoint(x: sx, y: 0)); $0.addLine(to: CGPoint(x: sx, y: size.height)) }
            if isMajor { major.addPath(line) } else { minor.addPath(line) }
            x += step
        }
        var y = (topLeft.y / step).rounded(.down) * step
        while y <= bottomRight.y {
            let sy = t.screen(ShapePoint(x: 0, y: y)).y
            let isMajor = abs((y / (step * 5)).rounded() * step * 5 - y) < 1e-6
            let line = Path { $0.move(to: CGPoint(x: 0, y: sy)); $0.addLine(to: CGPoint(x: size.width, y: sy)) }
            if isMajor { major.addPath(line) } else { minor.addPath(line) }
            y += step
        }
        context.stroke(minor, with: .color(.primary.opacity(0.06)), lineWidth: 0.5)
        context.stroke(major, with: .color(.primary.opacity(0.13)), lineWidth: 0.75)
    }

    private func drawBlank(_ context: inout GraphicsContext, t: Transform) {
        let b = bounds
        let rect = CGRect(origin: t.screen(ShapePoint(x: b.minX, y: b.minY)),
                          size: CGSize(width: b.width * t.scale, height: b.height * t.scale))
        context.stroke(Path(rect), with: .color(.secondary.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        context.draw(
            Text("Blank \(unit.format(b.width)) × \(unit.format(b.height)) \(unit.symbol)")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary),
            at: CGPoint(x: rect.minX, y: rect.minY - 6), anchor: .bottomLeading)
    }

    private func drawShape(_ context: inout GraphicsContext, t: Transform) {
        guard points.count >= 2 else { return }
        var path = Path()
        path.addLines(points.map(t.screen))
        path.closeSubpath()
        let color: Color = isValid ? .accentColor : .red
        context.fill(path, with: .color(color.opacity(0.18)))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        // Edge lengths, drawn just outside each edge.
        let clockwise = signedArea(points) > 0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            let length = PartShape.distance(a, b)
            guard length * t.scale > 44 else { continue }
            let sa = t.screen(a), sb = t.screen(b)
            let dx = sb.x - sa.x, dy = sb.y - sa.y
            let d = max(hypot(dx, dy), 1)
            // Outward normal for a clockwise (in screen space) polygon.
            let normal = clockwise ? CGPoint(x: dy / d, y: -dx / d) : CGPoint(x: -dy / d, y: dx / d)
            let mid = CGPoint(x: (sa.x + sb.x) / 2 + normal.x * 14, y: (sa.y + sb.y) / 2 + normal.y * 14)
            context.draw(Text(unit.format(length)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary), at: mid)
        }
    }

    private func drawGuides(_ context: inout GraphicsContext, size: CGSize, t: Transform) {
        for guide in guides {
            var path = Path()
            switch guide {
            case .vertical(let x):
                let sx = t.screen(ShapePoint(x: x, y: 0)).x
                path.move(to: CGPoint(x: sx, y: 0)); path.addLine(to: CGPoint(x: sx, y: size.height))
            case .horizontal(let y):
                let sy = t.screen(ShapePoint(x: 0, y: y)).y
                path.move(to: CGPoint(x: 0, y: sy)); path.addLine(to: CGPoint(x: size.width, y: sy))
            }
            context.stroke(path, with: .color(.pink), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    private func drawVertices(_ context: inout GraphicsContext, t: Transform) {
        let tint: Color = tool == .delete ? .red : .accentColor
        for (i, p) in points.enumerated() {
            let c = t.screen(p)
            let isSelected = i == selected
            let r: CGFloat = isSelected ? 9 : 7
            let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            context.fill(circle, with: .color(isSelected ? tint : Color(.systemBackground)))
            context.stroke(circle, with: .color(tint), lineWidth: 2)
        }
    }

    private func signedArea(_ pts: [ShapePoint]) -> Double {
        var sum = 0.0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let t = transform(for: canvasSize)
                if !gestureActive {
                    gestureActive = true
                    begin(at: value.startLocation, t: t)
                }
                guard let index = dragging, points.indices.contains(index) else { return }
                let raw = t.model(CGPoint(x: value.location.x + grabOffset.width, y: value.location.y + grabOffset.height))
                points[index] = snap(raw, excluding: index, t: t)
            }
            .onEnded { value in
                let t = transform(for: canvasSize)
                let moved = hypot(value.translation.width, value.translation.height) > 4
                if tool == .delete && !moved, let hit = hitVertex(value.location, t: t) {
                    deletePoint(hit)
                }
                if let last = undoStack.last, last == points { undoStack.removeLast() }
                dragging = nil
                gestureActive = false
                guides = []
                if !viewport.contains(bounds) { fitViewport() }
            }
    }

    private func begin(at location: CGPoint, t: Transform) {
        let hit = hitVertex(location, t: t)
        switch tool {
        case .move:
            selected = hit
            if let hit { startDragging(hit, from: location, t: t) }
        case .add:
            if let hit {
                selected = hit
                startDragging(hit, from: location, t: t)
            } else if let (edge, point) = hitEdge(location, t: t) {
                pushUndo()
                let snapped = snapOnEdge(point, edge: edge, t: t)
                points.insert(snapped, at: edge + 1)
                selected = edge + 1
                dragging = edge + 1
                grabOffset = .zero
            }
        case .delete:
            break
        }
    }

    private func startDragging(_ index: Int, from location: CGPoint, t: Transform) {
        pushUndo()
        dragging = index
        let c = t.screen(points[index])
        grabOffset = CGSize(width: c.x - location.x, height: c.y - location.y)
    }

    private func hitVertex(_ location: CGPoint, t: Transform) -> Int? {
        var best: (Int, CGFloat)?
        for (i, p) in points.enumerated() {
            let c = t.screen(p)
            let d = hypot(c.x - location.x, c.y - location.y)
            if d <= vertexHitRadius && (best == nil || d < best!.1) { best = (i, d) }
        }
        return best?.0
    }

    /// Nearest edge to `location` and the closest point on it, in model space.
    private func hitEdge(_ location: CGPoint, t: Transform) -> (Int, ShapePoint)? {
        var best: (Int, ShapePoint, CGFloat)?
        for i in points.indices {
            let a = t.screen(points[i]), b = t.screen(points[(i + 1) % points.count])
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { continue }
            let u = max(0, min(1, ((location.x - a.x) * dx + (location.y - a.y) * dy) / lengthSquared))
            let p = CGPoint(x: a.x + u * dx, y: a.y + u * dy)
            let d = hypot(p.x - location.x, p.y - location.y)
            if d <= edgeHitDistance && (best == nil || d < best!.2) { best = (i, t.model(p), d) }
        }
        return best.map { ($0.0, $0.1) }
    }

    // MARK: Snapping

    /// Snaps to alignment with other points (and the shape's centre lines) first,
    /// then to the grid on any axis that did not align.
    private func snap(_ raw: ShapePoint, excluding index: Int, t: Transform) -> ShapePoint {
        var result = raw
        var newGuides: Set<Guide> = []
        let threshold = snapDistance / t.scale
        let others = points.enumerated().filter { $0.offset != index }.map(\.element)

        if snapAlign && !others.isEmpty {
            let ob = PartShape.bounds(others)
            let xs = others.map(\.x) + [ob.midX]
            let ys = others.map(\.y) + [ob.midY]
            if let x = nearest(raw.x, in: xs, within: threshold) {
                result.x = x
                newGuides.insert(.vertical(x))
            }
            if let y = nearest(raw.y, in: ys, within: threshold) {
                result.y = y
                newGuides.insert(.horizontal(y))
            }
        }
        if snapGrid && gridSize > 0 {
            if !newGuides.contains(where: { if case .vertical = $0 { true } else { false } }) {
                result.x = (result.x / gridSize).rounded() * gridSize
            }
            if !newGuides.contains(where: { if case .horizontal = $0 { true } else { false } }) {
                result.y = (result.y / gridSize).rounded() * gridSize
            }
        }
        if newGuides != guides {
            if !newGuides.isEmpty { snapFeedback += 1 }
            guides = newGuides
        }
        return result
    }

    private func nearest(_ value: Double, in candidates: [Double], within threshold: Double) -> Double? {
        candidates
            .map { ($0, abs($0 - value)) }
            .filter { $0.1 <= threshold }
            .min { $0.1 < $1.1 }?.0
    }

    /// A new point on an edge snaps to the edge's midpoint, or to the grid along straight edges.
    private func snapOnEdge(_ point: ShapePoint, edge: Int, t: Transform) -> ShapePoint {
        let a = points[edge], b = points[(edge + 1) % points.count]
        let mid = ShapePoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        if snapAlign && PartShape.distance(point, mid) * t.scale <= snapDistance * 1.5 {
            snapFeedback += 1
            return mid
        }
        guard snapGrid && gridSize > 0 else { return point }
        if abs(a.y - b.y) < 1e-6 { return ShapePoint(x: (point.x / gridSize).rounded() * gridSize, y: a.y) }
        if abs(a.x - b.x) < 1e-6 { return ShapePoint(x: a.x, y: (point.y / gridSize).rounded() * gridSize) }
        return point
    }

    // MARK: Editing

    private func pushUndo() {
        undoStack.append(points)
        redoStack.removeAll()
    }

    private func deletePoint(_ index: Int) {
        guard points.count > 3 else { return }
        pushUndo()
        points.remove(at: index)
        selected = nil
    }

    private func apply(_ newPoints: [ShapePoint]) {
        pushUndo()
        points = newPoints
        selected = nil
        fitViewport()
    }

    private func flip(horizontal: Bool) {
        let b = bounds
        apply(points.reversed().map {
            horizontal ? ShapePoint(x: b.maxX - ($0.x - b.minX), y: $0.y) : ShapePoint(x: $0.x, y: b.maxY - ($0.y - b.minY))
        })
    }

    private func rotate() {
        let n = PartShape.normalized(points)
        apply(PartShape.rotatedClockwise(n, width: PartShape.bounds(n).height))
    }

    // MARK: Controls

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                if points != original { shape = points }
                dismiss()
            }
            .fontWeight(.semibold)
            .disabled(!isValid)
        }
    }

    /// Undo, redo, presets and snapping, shown above the tool picker.
    private var actionBar: some View {
        HStack(spacing: 4) {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                guard let last = undoStack.popLast() else { return }
                redoStack.append(points)
                points = last
                selected = nil
            }
            .disabled(undoStack.isEmpty)
            Button("Redo", systemImage: "arrow.uturn.forward") {
                guard let next = redoStack.popLast() else { return }
                undoStack.append(points)
                points = next
                selected = nil
            }
            .disabled(redoStack.isEmpty)
            Spacer()
            Menu {
                Section("Start From") {
                    ForEach(PartShape.Preset.allCases) { preset in
                        Button(preset.title, systemImage: preset.systemImage) {
                            let b = bounds
                            apply(preset.points(length: b.width, width: b.height))
                        }
                    }
                }
                Section("Transform") {
                    Button("Flip Horizontally", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { flip(horizontal: true) }
                    Button("Flip Vertically", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") { flip(horizontal: false) }
                    Button("Rotate 90°", systemImage: "rotate.right") { rotate() }
                }
            } label: {
                Label("Shapes", systemImage: "square.on.circle")
            }
            Menu {
                Toggle("Snap to Grid", systemImage: "grid", isOn: $snapGrid)
                Toggle("Snap to Alignment", systemImage: "align.horizontal.center", isOn: $snapAlign)
                Picker("Grid Size", selection: $gridSize) {
                    ForEach(gridOptions, id: \.self) { mm in
                        Text(unit.format(mm, includeSymbol: true)).tag(mm)
                    }
                }
                .pickerStyle(.menu)
            } label: {
                Label("Snapping", systemImage: snapGrid || snapAlign ? "squareshape.split.3x3" : "square.dashed")
            }
        }
        .buttonStyle(.bordered)
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
    }

    private var gridOptions: [Double] {
        if unit == .inches {
            let inches: [Double] = [0.0625, 0.125, 0.25, 0.5, 1]
            return inches.map { $0 * 25.4 }
        }
        return [1, 5, 10, 25, 50]
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let selected, points.indices.contains(selected) {
                HStack(spacing: 12) {
                    Text("Point \(selected + 1)")
                        .font(.subheadline.weight(.semibold))
                    LengthField("X", value: coordinate(selected, \.x))
                    LengthField("Y", value: coordinate(selected, \.y))
                    Button("Delete Point", systemImage: "trash", role: .destructive) { deletePoint(selected) }
                        .labelStyle(.iconOnly)
                        .disabled(points.count <= 3)
                }
                .id(selected)
            } else {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if isValid {
                    Text("\(points.count) points · Area \(areaText)")
                } else {
                    Label("Edges cross. Move the points so the outline doesn't overlap itself.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            actionBar

            Picker("Tool", selection: $tool) {
                ForEach(Tool.allCases) { tool in
                    Label(tool.title, systemImage: tool.systemImage).tag(tool)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(.bar)
    }

    private var areaText: String {
        let mm2 = PartShape.area(points)
        if unit == .inches {
            return (mm2 / 92_903.04).formatted(.number.precision(.fractionLength(2))) + " ft²"
        }
        return (mm2 / 1_000_000).formatted(.number.precision(.fractionLength(3))) + " m²"
    }

    private var hint: LocalizedStringKey {
        switch tool {
        case .move: "Drag a point to move it. Tap a point to type exact coordinates."
        case .add: "Tap an edge to add a point, or drag from an edge to pull a new point out."
        case .delete: "Tap a point to remove it. A shape needs at least three points."
        }
    }

    /// Coordinates are shown relative to the blank's top-left corner.
    private func coordinate(_ index: Int, _ key: WritableKeyPath<ShapePoint, Double>) -> Binding<Double> {
        Binding(
            get: {
                guard points.indices.contains(index) else { return 0 }
                let b = bounds
                return points[index][keyPath: key] - (key == \ShapePoint.x ? b.minX : b.minY)
            },
            set: { newValue in
                guard points.indices.contains(index) else { return }
                let b = bounds
                points[index][keyPath: key] = newValue + (key == \ShapePoint.x ? b.minX : b.minY)
            })
    }
}
