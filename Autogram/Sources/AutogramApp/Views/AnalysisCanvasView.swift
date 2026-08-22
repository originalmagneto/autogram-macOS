import SwiftUI
import PDFKit
import AutogramKit

struct AnalysisCanvasView: View {
    @Bindable var store: ZakoSessionStore
    @State private var interaction: Interaction?
    @State private var pageImage: NSImage?

    struct Interaction {
        enum Kind {
            case placing(UUID, NormalizedPoint)
            case moving(UUID)
            case resizing(UUID, NormalizedPoint)
        }
        var kind: Kind
        var startPoint: NormalizedPoint
        var moved: Bool = false
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 12) {
                pageBar
                pageImageLoader
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                countersRow
            }
            .padding(14)

            elementsPanel
                .frame(minWidth: 300, idealWidth: 330, maxWidth: 380)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await store.runAnalysis() }
                } label: {
                    Label("Znova analyzovať", systemImage: "arrow.clockwise")
                }
                .disabled(store.isAnalyzing)

                Spacer()

                Button {
                    store.step = .attestation
                } label: {
                    Text("Pokračovať na doložku")
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.glassProminent)
                .disabled(store.isAnalyzing || store.securityElements.isEmpty)
            }
        }
        .task(id: "\(store.previewPageIndex)-\(store.document == nil)") {
            renderPage()
        }
    }

    private func renderPage() {
        guard let document = store.document,
              let page = document.page(at: min(store.previewPageIndex,
                                               max(document.pageCount - 1, 0))) else {
            pageImage = nil
            return
        }
        let size = CGSize(width: 1240, height: 1754)
        pageImage = page.thumbnail(of: size, for: .mediaBox)
    }

    private var pageBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $store.activeTool) {
                Text("Vybrať / presunúť").tag(SecurityElement.Kind?.none)
                ForEach(SecurityElement.Kind.allCases, id: \.self) { kind in
                    Label(kind.rawValue, systemImage: kind.sfSymbol)
                        .tag(SecurityElement.Kind?.some(kind))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 260)

            if store.activeTool != nil {
                Button(role: .destructive) {
                    store.activeTool = nil
                } label: {
                    Label("Ukončiť pridávanie", systemImage: "xmark.circle.fill")
                        .font(.callout)
                }
                .buttonStyle(.glass)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    store.previewPageIndex = max(store.previewPageIndex - 1, 0)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(store.previewPageIndex <= 0)

                Text("Strana \(store.previewPageIndex + 1) z \(max(store.analysis.totalPages, 1))")
                    .font(.callout.monospacedDigit())
                    .frame(minWidth: 100)

                Button {
                    store.previewPageIndex = min(store.previewPageIndex + 1,
                                                 max(store.analysis.totalPages - 1, 0))
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(store.previewPageIndex >= max(store.analysis.totalPages - 1, 0))
            }
        }
    }

    private var pageImageLoader: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                Color(nsColor: .controlBackgroundColor).opacity(0.35)

                if let image = pageImage {
                    let fitter = ElementGeometry.AspectFitter(
                        container: geometry.size,
                        imageAspect: image.size.width / max(image.size.height, 1))

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        .overlay {
                            ElementOverlay(store: store,
                                           fitter: fitter,
                                           interaction: $interaction)
                        }
                } else if store.isAnalyzing {
                    ProgressView("Renderujem stranu…")
                } else {
                    Text("Žiadna strana na zobrazenie")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard(padding: 6)
            .clipped()
        }
    }

    private var countersRow: some View {
        HStack(spacing: 10) {
            StatChip(title: "Strany", value: "\(store.analysis.totalPages)", symbol: "doc.on.doc", tint: .blue)
            StatChip(title: "Neprázdne strany",
                     value: "\(store.analysis.nonEmptyPages)",
                     symbol: "doc.text.fill", tint: .teal)
            StatChip(title: "Listy (odhad duplex)",
                     value: "\(store.effectiveSheetCount)",
                     symbol: "rectangle.stack", tint: .indigo)
            StatChip(title: "Bezpečnostné prvky",
                     value: "\(store.securityElements.count)",
                     symbol: "shield.checkerboard", tint: .green)

            Spacer()

            Menu {
                Picker("Spôsob počítania listov", selection: $store.sheetMethod) {
                    ForEach(SheetCountingMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                if store.sheetMethod == .manual {
                    Stepper("Počet listov: \(store.manualSheetCount ?? store.analysis.estimatedSheetsDuplex)",
                            value: Binding(
                                get: { store.manualSheetCount ?? store.analysis.estimatedSheetsDuplex },
                                set: { store.manualSheetCount = $0 }),
                            in: 1...999)
                }
            } label: {
                Label("Listy", systemImage: "rectangle.stack.badge.plus")
            }
            .onChange(of: store.sheetMethod) { _, _ in
                store.applySheetMethodChange()
            }
        }
    }

    private var elementsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label("Bezpečnostné prvky — strana \(store.previewPageIndex + 1)",
                      systemImage: "shield.checkerboard")
                    .font(.headline)
                    .padding(.bottom, 2)

                if !store.unconfirmedNonEmptyPages.isEmpty && !store.isAnalyzing {
                    unconfirmedWarning
                }

                if store.lastDeletedElement != nil {
                    Button {
                        store.undoDelete()
                    } label: {
                        Label("Vrátiť odstránený prvok", systemImage: "arrow.uturn.backward")
                            .font(.callout)
                    }
                    .buttonStyle(.glass)
                }

                let pageElements = store.securityElements
                    .filter { $0.pageIndex == store.previewPageIndex }
                    .sorted { $0.boundingBox.y < $1.boundingBox.y }

                if pageElements.isEmpty && !store.isAnalyzing {
                    emptyHint
                }

                ForEach(pageElements) { element in
                    ElementRow(element: element,
                               isSelected: store.selectedElementID == element.id,
                               onSelect: { store.selectedElementID = element.id },
                               onDelete: {
                                   if store.selectedElementID == element.id {
                                       store.selectedElementID = nil
                                   }
                                   store.removeSecurityElement(id: element.id)
                               },
                               onDuplicate: { _ = store.duplicateElement(id: element.id) },
                               onKindChange: { kind in store.updateElementKind(id: element.id, kind: kind) },
                               onPageChange: { page in store.updateElementPage(id: element.id, pageIndex: page) },
                               onDescriptionChange: { text in
                                   store.updateElementDescription(id: element.id, text: text)
                               })
                }

                Divider().padding(.vertical, 6)

                if let tool = store.activeTool {
                    Label("Režim pridávania: \(tool.rawValue)", systemImage: "plus.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Klikni alebo ťahaj priamo v náhľade strany. Rukoväť vpravo dole mení veľkosť boxu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Režim „Vybrať“: klik vyberie prvok, ťahanie ho presúva, rukoväť vpravo dole mení veľkosť.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.vertical, 14)
        .padding(.trailing, 14)
    }

    private var unconfirmedWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Neprázdne strany bez potvrdených prvkov:", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
            FlowChips(pages: store.unconfirmedNonEmptyPages) { pageIndex in
                store.previewPageIndex = pageIndex
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Na tejto strane nie sú žiadne prvky.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if store.activeTool == nil {
                Text("Zvoľ nástroj hore a klikni do náhľadu pre manuálne pridanie pečiatky či podpisu.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct FlowChips: View {
    let pages: [Int]
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pages, id: \.self) { pageIndex in
                    Button {
                        onSelect(pageIndex)
                    } label: {
                        Text("Str. \(pageIndex + 1)")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.glass)
                    .tint(.orange)
                }
            }
        }
    }
}

struct ElementOverlay: View {
    @Bindable var store: ZakoSessionStore
    let fitter: ElementGeometry.AspectFitter
    @Binding var interaction: AnalysisCanvasView.Interaction?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, _ in
                for element in store.securityElements
                where element.pageIndex == store.previewPageIndex {
                    draw(context: context, element: element)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
    }

    private func draw(context: GraphicsContext, element: SecurityElement) {
        let rect = fitter.viewRect(for: element.boundingBox)
        guard rect.width > 1, rect.height > 1 else { return }
        let color = ElementKindColor.color(for: element.kind)
        let isSelected = store.selectedElementID == element.id

        context.fill(Path(roundedRect: rect, cornerRadius: 3),
                     with: .color(color.opacity(isSelected ? 0.22 : 0.10)))
        context.stroke(Path(roundedRect: rect, cornerRadius: 3),
                       with: .color(color),
                       lineWidth: isSelected ? 2.6 : 1.6)

        if isSelected {
            let handleSide: CGFloat = 10
            let handle = CGRect(x: rect.maxX - handleSide - 2,
                                y: rect.maxY - handleSide - 2,
                                width: handleSide,
                                height: handleSide)
            context.fill(Path(roundedRect: handle, cornerRadius: 2), with: .color(color))
            context.stroke(Path(roundedRect: handle, cornerRadius: 2),
                           with: .color(.white), lineWidth: 1.2)

            let labelText = "\(element.kind.rawValue) · \(Int(element.confidence * 100)) %"
            let labelSize = CGSize(width: 170, height: 14)
            let labelFrame = CGRect(x: rect.minX,
                                    y: max(rect.minY - labelSize.height - 2, 0),
                                    width: labelSize.width,
                                    height: labelSize.height)
            context.fill(Path(roundedRect: labelFrame, cornerRadius: 3),
                         with: .color(color.opacity(0.9)))
            context.draw(
                context.resolve(
                    Text(labelText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)),
                at: CGPoint(x: labelFrame.midX, y: labelFrame.midY),
                anchor: .center)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = fitter.normalizedPoint(from: value.location)

                if interaction == nil {
                    startInteraction(at: point)
                    return
                }

                switch interaction?.kind {
                case .placing(let id, let anchor):
                    interaction?.moved = true
                    store.drawElement(id: id, from: anchor, to: point)
                case .moving(let id):
                    interaction?.moved = true
                    store.moveElement(id: id, center: point)
                case .resizing(let id, let anchor):
                    interaction?.moved = true
                    store.drawElement(id: id, from: anchor, to: point)
                case nil:
                    break
                }
            }
            .onEnded { value in
                defer { interaction = nil }
                guard interaction == nil else {
                    if case .placing(let id, _) = interaction?.kind, interaction?.moved == false {
                        _ = id
                    }
                    return
                }

                let point = fitter.normalizedPoint(from: value.location)
                guard let tool = store.activeTool else {
                    store.selectedElementID = store.elementID(at: point,
                                                              pageIndex: store.previewPageIndex)
                    return
                }
                _ = store.placeElement(kind: tool, at: point, pageIndex: store.previewPageIndex)
            }
    }

    private func startInteraction(at point: NormalizedPoint) {
        if store.activeTool != nil {
            let id = store.placeElement(kind: store.activeTool!,
                                        at: point,
                                        pageIndex: store.previewPageIndex)
            interaction = .init(kind: .placing(id, point), startPoint: point)
            return
        }

        guard let hitID = store.elementID(at: point, pageIndex: store.previewPageIndex) else {
            store.selectedElementID = nil
            return
        }
        store.selectedElementID = hitID

        if store.isResizeHandle(hitID, at: point),
           let element = store.securityElements.first(where: { $0.id == hitID }) {
            let anchor = NormalizedPoint(x: element.boundingBox.x,
                                         y: element.boundingBox.y)
            interaction = .init(kind: .resizing(hitID, anchor), startPoint: point)
        } else {
            interaction = .init(kind: .moving(hitID), startPoint: point)
        }
    }
}

struct ElementRow: View {
    let element: SecurityElement
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onKindChange: (SecurityElement.Kind) -> Void
    let onPageChange: (Int) -> Void
    let onDescriptionChange: (String) -> Void

    @State private var descriptionDraft: String = ""
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: element.kind.sfSymbol)
                    .foregroundStyle(ElementKindColor.color(for: element.kind))
                    .frame(width: 20)

                Menu {
                    ForEach(SecurityElement.Kind.allCases, id: \.self) { kind in
                        Button(kind.rawValue) { onKindChange(kind) }
                    }
                } label: {
                    Text(element.kind.rawValue)
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderless)

                Spacer()

                Menu {
                    Button("Duplikovať") { onDuplicate() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 8) {
                Stepper("Strana \(element.pageIndex + 1)",
                        value: Binding(
                            get: { element.pageIndex },
                            set: { onPageChange(max($0, 0)) }),
                        in: 0...999)
                    .font(.caption.monospacedDigit())

                Spacer()

                if !element.detectedByAI {
                    Text("manuálne")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15), in: Capsule())
                        .foregroundStyle(.purple)
                } else {
                    ConfidenceBar(confidence: element.confidence)
                    Text("\(Int(element.confidence * 100)) %")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Slovný opis pre doložku",
                      text: Binding(
                          get: {
                              descriptionFocused || !descriptionDraft.isEmpty
                                  ? descriptionDraft
                                  : element.verbalDescription
                          },
                          set: { newValue in
                              descriptionDraft = newValue
                              onDescriptionChange(newValue)
                          }),
                      axis: .vertical)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)
                .focused($descriptionFocused)
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
