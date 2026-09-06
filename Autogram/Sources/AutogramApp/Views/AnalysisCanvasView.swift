import SwiftUI
import PDFKit
import AutogramKit

struct AnalysisCanvasView: View {
    @Bindable var store: ZakoSessionStore
    @State private var showPrecisePlacement = false
    @State private var interaction: Interaction?
    @State private var pageImage: NSImage?
    @State private var pageAspect: CGFloat = 1.414

    struct Interaction {
        enum Kind {
            case moving(UUID)
            case resizing(UUID, NormalizedPoint)
        }
        var kind: Kind
        var startPoint: NormalizedPoint
        var moved: Bool = false
        /// True only when this interaction placed a brand-new placeholder element
        /// (via store.placeElement), so a click-without-drag on it should snap.
        var created: Bool = false
    }

    /// Maps between view coordinates (y=0 top) and the domain convention
    /// (normalized y=0 page BOTTOM, PDF semantics) used by SecurityElement boxes.
    struct CanvasMapper {
        let fitter: ElementGeometry.AspectFitter

        func viewRect(for normalized: NormalizedRect) -> CGRect {
            fitter.viewRect(for: NormalizedRect(
                x: normalized.x,
                y: 1 - normalized.y - normalized.height,
                width: normalized.width,
                height: normalized.height))
        }

        func normalizedPoint(from viewPoint: CGPoint) -> NormalizedPoint {
            let topDown = fitter.normalizedPoint(from: viewPoint)
            return NormalizedPoint(x: topDown.x, y: 1 - topDown.y)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let warning = store.analysisWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
            }

            HSplitView {
                HStack(spacing: 0) {
                    if store.analysis.totalPages > 1 {
                        pageThumbnailStrip
                            .frame(width: 80)
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
                            }
                    }

                    VStack(spacing: 10) {
                        pageImageLoader
                            .frame(minWidth: MacOS27Layout.canvasMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
                        countersRow
                    }
                    .padding(14)
                }

                elementsPanel
                    .frame(minWidth: MacOS27Layout.inspectorMinimumWidth,
                           idealWidth: MacOS27Layout.inspectorIdealWidth,
                           maxWidth: 400)
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
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                detectionProviderPicker
                sheetCountMenu
                pageNavBar
            }
        }
    }

    private func renderPage() {
        guard let document = store.document,
              let page = document.page(at: min(store.previewPageIndex,
                                               max(document.pageCount - 1, 0))),
              let rendered = BuiltInVisionProvider.render(page: page, targetWidth: 1240) else {
            pageImage = nil
            return
        }
        // Rotation-aware render: displayed bitmap and aspect agree with the page
        // as the user sees it (/Rotate honored).
        let cg = rendered.cgImage
        pageImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        pageAspect = CGFloat(cg.width) / max(CGFloat(cg.height), 1)
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
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 54, height: 72)
                                .overlay {
                                    if let page = store.document?.page(at: pageIndex) {
                                        Image(nsImage: page.thumbnail(
                                            of: CGSize(width: 108, height: 144),
                                            for: .mediaBox))
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 52, height: 70)
                                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                                )

                            Text("\(pageIndex + 1)")
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .padding(.horizontal, 4)
                                .padding(4)
                                .background(.regularMaterial, in: Capsule())

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
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Markup Toolbar
    /// Manual marking lives in the inspector, not over the page: pick a kind,
    /// then click the element in the document. Picking it again leaves the mode.
    private var addElementCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pridať prvok", systemImage: "plus.circle")
                .font(.headline)
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    toolButton(kind: .officialStamp, title: "Pečiatka", icon: "seal.fill")
                    toolButton(kind: .handwrittenSignature, title: "Podpis", icon: "signature")
                }
                GridRow {
                    toolButton(kind: .embossedSeal, title: "Pečať", icon: "rosette")
                    toolButton(kind: .initial, title: "Parafa", icon: "text.badge.checkmark")
                }
            }
            if let progress = store.snapAssetProgress {
                HStack(spacing: 6) {
                    ProgressView(value: progress).frame(width: 80)
                    Text("Sťahujem model výberu…").font(.caption2).foregroundStyle(.secondary)
                }
            } else if let reason = store.snapUnavailableReason {
                Text(reason).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(store.activeTool == nil
                     ? "Zvoľte typ a kliknite na prvok v dokumente; rámec sa prichytí k jeho obrysu."
                     : "Kliknite na prvok v dokumente. Ťahaním nakreslíte rámec ručne.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard(cornerRadius: 12, padding: 12)
    }

    /// Indicator + inline switcher for the detection provider. Apple Vision
    /// (on-device) always runs; the selected mode only adds LLM findings.
    private var detectionProviderPicker: some View {
        let currentMode = store.settingsStore.settings.aiMode
        return Menu {
            Picker("Poskytovateľ detekcie", selection: Binding(
                get: { store.settingsStore.settings.aiMode },
                set: { store.settingsStore.settings.aiMode = $0 })) {
                ForEach(AppSettings.AIMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: icon(for: mode)).tag(mode)
                }
            }

        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                Text("Detekcia: \(currentMode.rawValue)")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .menuStyle(.borderedButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Apple Vision beží vždy on-device; zvolený režim dopĺňa LLM klasifikáciu. Zmena sa prejaví pri ďalšej analýze.")
    }

    private func icon(for mode: AppSettings.AIMode) -> String {
        switch mode {
        case .omlxLocal: return "apple.logo"
        case .ollamaLocal: return "laptopcomputer"
        case .builtInOnDevice: return "bolt.badge.checkmark"
        case .customAPIKey: return "key.fill"
        case .disabled: return "xmark.circle"
        }
    }

    private var pageNavBar: some View {
        HStack(spacing: 8) {
            Button {
                store.previewPageIndex = max(store.previewPageIndex - 1, 0)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(store.previewPageIndex <= 0)
            .controlSize(.small)
            .accessibilityLabel("Predchádzajúca strana")

            Text("Strana \(store.previewPageIndex + 1) z \(max(store.analysis.totalPages, 1))")
                .font(.caption.monospacedDigit().weight(.medium))
                .fixedSize()

            Button {
                store.previewPageIndex = min(store.previewPageIndex + 1,
                                             max(store.analysis.totalPages - 1, 0))
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(store.previewPageIndex >= max(store.analysis.totalPages - 1, 0))
            .controlSize(.small)
            .accessibilityLabel("Nasledujúca strana")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func toolButton(kind: SecurityElement.Kind, title: String, icon: String) -> some View {
        let isSelected = store.activeTool == kind
        return Button {
            store.activeTool = isSelected ? nil : kind
        } label: {
            Label(title, systemImage: icon)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }


    private var pageImageLoader: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                Color(nsColor: .controlBackgroundColor).opacity(0.35)

                if let image = pageImage {
                    // Fitter over the whole canvas resolves the letterboxed page rect.
                    let canvasFitter = ElementGeometry.AspectFitter(
                        container: geometry.size,
                        imageAspect: pageAspect)

                    // Image sized exactly to the page rect; overlay covers the same frame,
                    // so normalized coordinates stay anchored to the document at any size.
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: canvasFitter.contentRect.width,
                               height: canvasFitter.contentRect.height)
                        .overlay {
                            ElementOverlay(
                                store: store,
                                mapper: AnalysisCanvasView.CanvasMapper(
                                    fitter: ElementGeometry.AspectFitter(
                                        container: canvasFitter.contentRect.size,
                                        imageAspect: pageAspect)),
                                interaction: $interaction)
                        }
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
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
                            Label("\(tool.rawValue): kliknite na prvok v dokumente", systemImage: "plus.viewfinder")
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
                if store.isAnalyzing {
                    analysisOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// Covers the canvas while detection runs: the dimming layer also swallows
    /// clicks, so nobody edits boxes that the finishing run is about to replace.
    private var analysisOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())

            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.large)
                Text("Analyzujem dokument")
                    .font(.headline)
                if !store.analysisProgressText.isEmpty {
                    Text(store.analysisProgressText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("Nálezy sa zobrazia po dokončení. Kontrola každej strany zostáva na vás.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prebieha analýza dokumentu")
    }

    /// One quiet line under the page instead of four chips: the numbers matter,
    /// the decoration competed with the document.
    private var countersRow: some View {
        Text([
            SlovakCount.phrase(store.analysis.totalPages, "strana", "strany", "strán"),
            "\(store.analysis.nonEmptyPages) neprázdne",
            SlovakCount.phrase(store.effectiveSheetCount, "list", "listy", "listov") + " (odhad)",
            SlovakCount.phrase(store.securityElements.count, "prvok", "prvky", "prvkov")
        ].joined(separator: " · "))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Súhrn dokumentu")
    }

    private var sheetCountMenu: some View {
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
    private var elementsPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    pageReviewCard
                    findingsCard
                    addElementCard
                }
                .padding(12)
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
        }
    }

    /// Findings of the current page plus the collapsed numeric inspector.
    private var findingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Nálezy", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                if store.lastDeletedElement != nil {
                    Button {
                        store.undoDelete()
                    } label: {
                        Label("Vrátiť", systemImage: "arrow.uturn.backward")
                    }
                    .controlSize(.small)
                    .help("Vrátiť zmazaný prvok")
                }
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
                                   onRefine: { Task { await store.refineElement(id: element.id) } },
                                   onReviewStateChange: { state in
                                       switch state {
                                       case .confirmed: store.confirmSecurityElement(id: element.id)
                                       case .rejected: store.rejectSecurityElement(id: element.id)
                                        case .pending: store.returnSecurityElementToReview(id: element.id)
                                       }
                                   },
                                   onKindChange: { kind in store.updateElementKind(id: element.id, kind: kind) },
                                   onDescriptionChange: { text in
                                       store.updateElementDescription(id: element.id, text: text)
                                   })
                    }

            if store.selectedElementID != nil {
                DisclosureGroup("Presná poloha", isExpanded: $showPrecisePlacement) {
                    selectedElementInspector
                }
                .font(.caption.weight(.semibold))
                .help("Číselné umiestnenie a klávesové posuny. Ťahanie na plátne a klik na prvok sú rýchlejšie.")
            }
        }
        .glassCard(cornerRadius: 12, padding: 12)
    }

    /// Review status of the current page: counts, the reviewed toggle, and the
    /// pages that still need a look.
    private var pageReviewCard: some View {
        let pageIndex = store.previewPageIndex
        let isReviewed = store.reviewedNonEmptyPages.contains(pageIndex)
        let isEmptyPage = store.analysis.pageAnalyses.first(where: { $0.pageIndex == pageIndex })?.isEmpty != false
        let rejected = store.securityElements.filter { $0.reviewState == .rejected }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Kontrola strany", systemImage: "checkmark.shield")
                    .font(.headline)
                Spacer()
                Text("Strana \(pageIndex + 1) z \(max(store.analysis.totalPages, 1))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("\(store.confirmedSecurityElements.count) potvrdené · \(store.pendingSecurityElementCount) čaká · \(rejected) odmietnuté")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                if isReviewed { store.unmarkPageReviewed(pageIndex) } else { store.markPageReviewed(pageIndex) }
            } label: {
                Label(isReviewed ? "Strana skontrolovaná" : "Označiť stranu ako skontrolovanú",
                      systemImage: isReviewed ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isReviewed ? .green : .accentColor)
            .disabled(isEmptyPage)
            .help(isReviewed ? "Kliknutím zrušíte označenie" : "Každá neprázdna strana musí byť skontrolovaná")

            if !store.unconfirmedNonEmptyPages.isEmpty && !store.isAnalyzing {
                unconfirmedWarning
            }
        }
        .glassCard(cornerRadius: 12, padding: 12)
    }

    @ViewBuilder
    private var selectedElementInspector: some View {
        if let element = store.securityElements.first(where: { $0.id == store.selectedElementID }) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Vybraný prvok: \(element.kind.rawValue)", systemImage: element.kind.sfSymbol)
                    .font(.caption.weight(.semibold))
                Text("Umiestnenie a veľkosť (0 až 1)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        normalizedField("X", value: element.boundingBox.x) { value in
                            updateBoundingBox(element.id) { $0.x = value }
                        }
                        normalizedField("Y", value: element.boundingBox.y) { value in
                            updateBoundingBox(element.id) { $0.y = value }
                        }
                    }
                    GridRow {
                        normalizedField("Šírka", value: element.boundingBox.width) { value in
                            updateBoundingBox(element.id) { $0.width = value }
                        }
                        normalizedField("Výška", value: element.boundingBox.height) { value in
                            updateBoundingBox(element.id) { $0.height = value }
                        }
                    }
                }

                HStack(spacing: 6) {
                    Text("Posun")
                        .font(.caption2.weight(.semibold))
                    placementButton("doľava", icon: "arrow.left", shortcut: .leftArrow) {
                        adjustSelectedElement(dx: -0.01, dy: 0)
                    }
                    placementButton("doprava", icon: "arrow.right", shortcut: .rightArrow) {
                        adjustSelectedElement(dx: 0.01, dy: 0)
                    }
                    placementButton("hore", icon: "arrow.up", shortcut: .upArrow) {
                        adjustSelectedElement(dx: 0, dy: 0.01)
                    }
                    placementButton("dole", icon: "arrow.down", shortcut: .downArrow) {
                        adjustSelectedElement(dx: 0, dy: -0.01)
                    }
                }

                HStack(spacing: 6) {
                    Text("Veľkosť")
                        .font(.caption2.weight(.semibold))
                    placementButton("zmenšiť šírku", icon: "arrow.left.and.right", shortcut: .leftArrow, modifiers: [.shift]) {
                        adjustSelectedElement(dx: 0, dy: 0, dw: -0.01, dh: 0)
                    }
                    placementButton("zväčšiť šírku", icon: "arrow.left.and.right", shortcut: .rightArrow, modifiers: [.shift]) {
                        adjustSelectedElement(dx: 0, dy: 0, dw: 0.01, dh: 0)
                    }
                    placementButton("zmenšiť výšku", icon: "arrow.up.and.down", shortcut: .downArrow, modifiers: [.shift]) {
                        adjustSelectedElement(dx: 0, dy: 0, dw: 0, dh: -0.01)
                    }
                    placementButton("zväčšiť výšku", icon: "arrow.up.and.down", shortcut: .upArrow, modifiers: [.shift]) {
                        adjustSelectedElement(dx: 0, dy: 0, dw: 0, dh: 0.01)
                    }
                }
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityValue("\(UXLabels.confidenceLabel(for: element.confidence)); \(UXLabels.provenanceLabel(detectedByAI: element.detectedByAI))")
        }
    }

    private func normalizedField(_ label: String, value: Double,
                                onChange: @escaping (Double) -> Void) -> some View {
        TextField(label, value: Binding(
            get: { value },
            set: { onChange($0) }
        ), format: .number.precision(.fractionLength(3)))
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 72)
        .accessibilityLabel(label)
    }

    private func updateBoundingBox(_ id: UUID, update: (inout NormalizedRect) -> Void) {
        guard var box = store.securityElements.first(where: { $0.id == id })?.boundingBox else { return }
        update(&box)
        store.updateElementBoundingBox(id: id, boundingBox: box)
    }

    private func adjustSelectedElement(dx: Double, dy: Double, dw: Double = 0, dh: Double = 0) {
        guard let element = store.securityElements.first(where: { $0.id == store.selectedElementID }) else { return }
        var box = element.boundingBox
        box.x += dx
        box.y += dy
        box.width += dw
        box.height += dh
        store.updateElementBoundingBox(id: element.id, boundingBox: box)
    }

    private func placementButton(_ label: String, icon: String, shortcut: KeyEquivalent,
                                 modifiers: EventModifiers = [], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(label)
        .keyboardShortcut(shortcut, modifiers: modifiers)
    }

    private var unconfirmedWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Neskontrolované neprázdne strany:", systemImage: "exclamationmark.triangle.fill")
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
        Text("Žiadne prvky. Zvoľte nástroj a kliknite na prvok v dokumente.")
            .font(.callout)
            .foregroundStyle(.secondary)
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
    let mapper: AnalysisCanvasView.CanvasMapper
    @Binding var interaction: AnalysisCanvasView.Interaction?

    private let handleRadius: CGFloat = 14

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
        let rect = mapper.viewRect(for: element.boundingBox)
        guard rect.width > 1, rect.height > 1 else { return }
        let color = ElementKindColor.color(for: element.kind)
        let isSelected = store.selectedElementID == element.id

        context.fill(Path(roundedRect: rect, cornerRadius: 4),
                     with: .color(color.opacity(isSelected ? 0.22 : 0.10)))
        context.stroke(Path(roundedRect: rect, cornerRadius: 4),
                       with: .color(color),
                       lineWidth: isSelected ? 2.5 : 1.5)

        if isSelected {
            // Corner resize handles on all four corners.
            for corner in cornerPoints(of: rect) {
                let handle = CGRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10)
                context.fill(Path(roundedRect: handle, cornerRadius: 2), with: .color(color))
                context.stroke(Path(roundedRect: handle, cornerRadius: 2),
                               with: .color(.white), lineWidth: 1.2)
            }

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

    private func cornerPoints(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
    }

    /// Returns the normalized point of the corner OPPOSITE to the grabbed corner,
    /// or nil when the point is not near any corner (with handleRadius tolerance).
    private func oppositeCornerAnchor(of box: NormalizedRect, at viewPoint: CGPoint) -> NormalizedPoint? {
        let rect = mapper.viewRect(for: box)
        let corners: [(CGFloat, CGFloat)] = [
            (rect.minX, rect.minY), (rect.maxX, rect.minY),
            (rect.minX, rect.maxY), (rect.maxX, rect.maxY)
        ]
        let grabbed = corners.first { hypot(viewPoint.x - $0.0, viewPoint.y - $0.1) <= handleRadius }
        guard let grabbed else { return nil }
        return NormalizedPoint(
            x: grabbed.0 == rect.minX ? box.x + box.width : box.x,
            y: grabbed.1 == rect.minY ? box.y + box.height : box.y)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                defer { interaction = nil }
                guard let current = interaction, !current.moved, current.created,
                      case .resizing(let id, _) = current.kind,
                      store.activeTool != nil else { return }
                // A click without movement right after placing a new element: snap its box in place.
                let point = mapper.normalizedPoint(from: value.location)
                Task { @MainActor in
                    await store.snapPlacedElement(id: id, at: point)
                }
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let normPoint = mapper.normalizedPoint(from: value.location)

        if interaction == nil {
            if let hitID = store.elementID(at: normPoint, pageIndex: store.previewPageIndex),
               let element = store.securityElements.first(where: { $0.id == hitID }) {
                store.selectedElementID = hitID
                if let anchor = oppositeCornerAnchor(of: element.boundingBox, at: value.location) {

                    interaction = .init(kind: .resizing(hitID, anchor), startPoint: anchor)
                } else {
                    interaction = .init(kind: .moving(hitID), startPoint: normPoint)
                }
                return
            }

            if let tool = store.activeTool {
                let newID = store.placeElement(kind: tool, at: normPoint)
                interaction = .init(kind: .resizing(newID, normPoint), startPoint: normPoint, created: true)
                return
            }

            store.selectedElementID = nil
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
        }
    }
}

struct ElementRow: View {
    let element: SecurityElement
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onRefine: () -> Void
    let onReviewStateChange: (SecurityElementReviewState) -> Void
    let onKindChange: (SecurityElement.Kind) -> Void
    let onDescriptionChange: (String) -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: kind (as the menu label itself) and confidence.
            HStack(spacing: 8) {
                Button(action: onSelect) {
                    Image(systemName: element.kind.sfSymbol)
                        .foregroundStyle(ElementKindColor.color(for: element.kind))
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(element.kind.rawValue), stav: \(element.reviewState.label), \(UXLabels.provenanceLabel(detectedByAI: element.detectedByAI))")
                .accessibilityValue("\(UXLabels.confidenceLabel(for: element.confidence)); \(isSelected ? "Vybraný" : "Nevybraný")")
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                Menu {
                    ForEach(SecurityElement.Kind.allCases, id: \.self) { kind in
                        Button {
                            onKindChange(kind)
                        } label: {
                            Label(kind.rawValue, systemImage: kind.sfSymbol)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(element.kind.rawValue)
                            .font(.callout.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Typ prvku")
                .accessibilityValue(element.kind.rawValue)

                Spacer(minLength: 6)

                ConfidenceBar(confidence: element.confidence)
                Text(UXLabels.confidenceLabel(for: element.confidence))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .lineLimit(1)

            // Row 2: description.
            TextField("Popis prvku", text: Binding(
                get: { element.verbalDescription },
                set: { onDescriptionChange($0) }
            ), axis: .vertical)
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Popis prvku")

            // Row 3: review state and actions. Every label is fixed-size so nothing
            // wraps mid-word in a narrow sidebar.
            HStack(alignment: .center, spacing: 6) {
                Label(element.reviewState.label, systemImage: reviewIcon)
                    .font(.caption2)
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
                    .foregroundStyle(reviewColor)

                Spacer(minLength: 6)

                if element.reviewState == .pending {
                    Button("Potvrdiť") {
                        onReviewStateChange(.confirmed)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .fixedSize()
                    Button("Odmietnuť") {
                        onReviewStateChange(.rejected)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                } else if element.reviewState == .rejected {
                    Button("Vrátiť na kontrolu") {
                        onReviewStateChange(.pending)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                }

                Button {
                    onDuplicate()
                } label: {
                    Label("Duplikovať prvok", systemImage: "plus.square.on.square")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Duplikovať prvok")
                .foregroundStyle(.secondary)

                Button {
                    onRefine()
                } label: {
                    Label("Spresniť rámec", systemImage: "wand.and.stars")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Spresniť rámec podľa obrysu (Apple Vision)")
                .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Odstrániť prvok", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Odstrániť prvok")
                .foregroundStyle(.red)
            }
            .lineLimit(1)

            // Row 4: how this element was found.
            Text(sourceCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .confirmationDialog("Naozaj chcete odstrániť tento prvok?",
                           isPresented: $showDeleteConfirmation,
                           titleVisibility: .visible) {
            Button("Odstrániť prvok", role: .destructive, action: onDelete)
            Button("Zrušiť", role: .cancel) {}
        } message: {
            Text("Prvok bude odstránený z doložky. Túto zmenu môžete vrátiť tlačidlom Späť.")
        }
    }

    private var sourceCaption: String {
        DetectionSourceLabel.slovak(element.detectionSource)
    }

    private var reviewIcon: String {
        switch element.reviewState {
        case .pending: return "questionmark.circle"
        case .confirmed: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle.fill"
        }
    }

    private var reviewColor: Color {
        switch element.reviewState {
        case .pending: return .orange
        case .confirmed: return .green
        case .rejected: return .secondary
        }
    }
}

/// Slovak count phrases: 1 strana, 2-4 strany, 5+ strán.
enum SlovakCount {
    static func phrase(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let word: String
        switch n {
        case 1: word = one
        case 2...4: word = few
        default: word = many
        }
        return "\(n) \(word)"
    }
}
