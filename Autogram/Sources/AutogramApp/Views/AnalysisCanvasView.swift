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
        VStack(spacing: 0) {
            HSplitView {
                HStack(spacing: 0) {
                    if store.analysis.totalPages > 1 {
                        pageThumbnailStrip
                            .frame(width: 80)
                            .background(.bar)
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
                            }
                    }

                    VStack(spacing: 10) {
                        markupToolbar
                        pageImageLoader
                            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                        countersRow
                    }
                    .padding(14)
                }

                elementsPanel
                    .frame(minWidth: 320, idealWidth: 350, maxWidth: 400)
            }

            StickyActionBar {
                Button {
                    store.resetSession(keepingProfile: true)
                    store.step = .intake
                } label: {
                    Label("Iný dokument", systemImage: "chevron.left")
                }
                .controlSize(.large)

                Button {
                    Task { await store.runAnalysis() }
                } label: {
                    Label("Znova analyzovať AI", systemImage: "arrow.clockwise")
                }
                .disabled(store.isAnalyzing)
                .controlSize(.large)

                Spacer()

                Button {
                    store.step = .attestation
                } label: {
                    HStack(spacing: 6) {
                        Text("Pokračovať na doložku")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isAnalyzing)
                .keyboardShortcut(.defaultAction)
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

    // MARK: - Left Page Thumbnail Strip
    private var pageThumbnailStrip: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 8) {
                ForEach(0..<store.analysis.totalPages, id: \.self) { pageIndex in
                    let isSelected = store.previewPageIndex == pageIndex
                    let countOnPage = store.securityElements.filter { $0.pageIndex == pageIndex }.count

                    Button {
                        store.previewPageIndex = pageIndex
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(isSelected ? 0.12 : 0.04))
                                    .frame(width: 54, height: 72)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                                    )

                                Text("\(pageIndex + 1)")
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    .padding(4)

                                if countOnPage > 0 {
                                    Text("\(countOnPage)")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.green, in: Capsule())
                                        .foregroundStyle(.white)
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Markup Floating Toolbar
    private var markupToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                toolButton(kind: nil, title: "Vybrať", icon: "arrow.up.left.and.arrow.down.right")
                Divider().frame(height: 18)
                toolButton(kind: .officialStamp, title: "Pečiatka", icon: "seal.fill")
                toolButton(kind: .handwrittenSignature, title: "Podpis", icon: "signature")
                toolButton(kind: .embossedSeal, title: "Pečať", icon: "rosette")
                toolButton(kind: .initial, title: "Parafa", icon: "text.badge.checkmark")
            }
            .padding(4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Spacer()

            HStack(spacing: 8) {
                Button {
                    store.previewPageIndex = max(store.previewPageIndex - 1, 0)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(store.previewPageIndex <= 0)
                .controlSize(.small)

                Text("Strana \(store.previewPageIndex + 1) z \(max(store.analysis.totalPages, 1))")
                    .font(.callout.monospacedDigit().weight(.medium))
                    .frame(minWidth: 100)

                Button {
                    store.previewPageIndex = min(store.previewPageIndex + 1,
                                                 max(store.analysis.totalPages - 1, 0))
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(store.previewPageIndex >= max(store.analysis.totalPages - 1, 0))
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func toolButton(kind: SecurityElement.Kind?, title: String, icon: String) -> some View {
        let isSelected = store.activeTool == kind
        return Button {
            store.activeTool = kind
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
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
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.regular)
                        Text("Analyzujem bezpečnostné prvky…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Žiadna strana na zobrazenie")
                        .foregroundStyle(.secondary)
                }

                if let tool = store.activeTool {
                    VStack {
                        HStack {
                            Label("Režim pridávania: \(tool.rawValue) - kliknite na plátno", systemImage: "plus.viewfinder")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.9), in: Capsule())
                                .foregroundStyle(.white)
                                .shadow(radius: 4)

                            Spacer()
                        }
                        .padding(10)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liquidGlass(cornerRadius: 18, padding: 6)
            .clipped()
        }
    }

    private var countersRow: some View {
        HStack(spacing: 10) {
            StatChip(title: "Strany", value: "\(store.analysis.totalPages)", symbol: "doc.on.doc", tint: .blue)
            StatChip(title: "Neprázdne",
                     value: "\(store.analysis.nonEmptyPages)",
                     symbol: "doc.text.fill", tint: .teal)
            StatChip(title: "Listy (odhad)",
                     value: "\(store.effectiveSheetCount)",
                     symbol: "rectangle.stack", tint: .indigo)
            StatChip(title: "Prvky",
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
                Label("Spôsob: \(store.sheetMethod.rawValue)", systemImage: "rectangle.stack.badge.plus")
                    .font(.caption)
            }
            .onChange(of: store.sheetMethod) { _, _ in
                store.applySheetMethodChange()
            }
        }
    }

    private var elementsPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Prvky: strana \(store.previewPageIndex + 1)", systemImage: "shield.checkerboard")
                            .font(.headline)
                        Spacer()
                        if store.lastDeletedElement != nil {
                            Button {
                                store.undoDelete()
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .help("Vrátiť zmazaný prvok")
                            .controlSize(.small)
                        }
                    }

                    if !store.unconfirmedNonEmptyPages.isEmpty && !store.isAnalyzing {
                        unconfirmedWarning
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

                    Divider().padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pridanie a úprava:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Vyberte nástroj hore a kliknite do náhľadu. Bounding box môžete presúvať a vpravo dole meniť jeho veľkosť.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(16)
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
        }
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
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Na tejto strane zatiaľ nie sú detegované prvky.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Zvoľte nástroj hore v lište a kliknite do dokumentu pre manuálne pridanie.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
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
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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

        context.fill(Path(roundedRect: rect, cornerRadius: 4),
                     with: .color(color.opacity(isSelected ? 0.22 : 0.10)))
        context.stroke(Path(roundedRect: rect, cornerRadius: 4),
                       with: .color(color),
                       lineWidth: isSelected ? 2.5 : 1.5)

        if isSelected {
            let handleSide: CGFloat = 10
            let handle = CGRect(x: rect.maxX - handleSide - 2,
                                y: rect.maxY - handleSide - 2,
                                width: handleSide,
                                height: handleSide)
            context.fill(Path(roundedRect: handle, cornerRadius: 2), with: .color(color))
            context.stroke(Path(roundedRect: handle, cornerRadius: 2),
                           with: .color(.white), lineWidth: 1.2)

            let labelText = "\(element.kind.rawValue) (\(Int(element.confidence * 100)) %)"
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
                handleDragChanged(value)
            }
            .onEnded { _ in
                interaction = nil
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let normPoint = fitter.normalizedPoint(from: value.location)

        if interaction == nil {
            if let tool = store.activeTool {
                let newID = store.placeElement(kind: tool, at: normPoint)
                interaction = .init(kind: .resizing(newID, normPoint), startPoint: normPoint)
                return
            }

            if let hitID = store.elementID(at: normPoint, pageIndex: store.previewPageIndex) {
                store.selectedElementID = hitID
                if let element = store.securityElements.first(where: { $0.id == hitID }),
                   ElementGeometry.isInResizeHandle(element.boundingBox, normPoint) {
                    interaction = .init(kind: .resizing(hitID, normPoint), startPoint: normPoint)
                } else {
                    interaction = .init(kind: .moving(hitID), startPoint: normPoint)
                }
            } else {
                store.selectedElementID = nil
            }
            return
        }

        guard let current = interaction else { return }
        switch current.kind {
        case .moving(let id):
            store.moveElement(id: id, center: normPoint)
            interaction?.moved = true
        case .resizing(let id, _):
            store.drawElement(id: id, from: current.startPoint, to: normPoint)
            interaction?.moved = true
        case .placing:
            break
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: element.kind.sfSymbol)
                    .foregroundStyle(ElementKindColor.color(for: element.kind))
                    .frame(width: 18)

                Picker("", selection: Binding(get: { element.kind }, set: { onKindChange($0) })) {
                    ForEach(SecurityElement.Kind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()

                ConfidenceBar(confidence: element.confidence)

                Menu {
                    Button("Duplikovať", action: onDuplicate)
                    Divider()
                    Button("Odstrániť", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 16)
            }

            if !element.verbalDescription.isEmpty {
                Text(element.verbalDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
