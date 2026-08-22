import SwiftUI
import AutogramKit

struct AnalysisCanvasView: View {
    @Bindable var store: ZakoSessionStore
    @State private var selectedTool: SecurityElement.Kind = .officialStamp
    @State private var selectedElementID: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 12) {
                documentPreview
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
                .buttonStyle(.borderedProminent)
                .disabled(store.isAnalyzing)
            }
        }
    }

    private var documentPreview: some View {
        ZStack(alignment: .topLeading) {
            if let document = store.document {
                PDFKitPreview(document: document)
            } else {
                Text("Žiadny dokument")
            }
            GeometryReader { geometry in
                Canvas { context, _ in
                    for element in store.securityElements {
                        let rect = scaledRect(element.boundingBox,
                                              pageIndex: element.pageIndex,
                                              in: geometry.size)
                        let color = ElementKindColor.color(for: element.kind)
                        context.stroke(Path(roundedRect: rect, cornerRadius: 4),
                                      with: .color(color),
                                      lineWidth: selectedElementID == element.id ? 3 : 1.8)
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: 4),
                            with: .color(color.opacity(selectedElementID == element.id ? 0.22 : 0.10)))
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .glassCard(padding: 6)
    }

    private func scaledRect(_ box: NormalizedRect, pageIndex: Int, in size: CGSize) -> CGRect {
        guard let pdfViewPageCount = store.document?.pageCount, pdfViewPageCount > 0 else { return .zero }
        return CGRect(x: box.x * size.width,
                      y: box.y * size.height,
                      width: box.width * size.width,
                      height: box.height * size.height)
    }

    private var countersRow: some View {
        HStack(spacing: 10) {
            StatChip(title: "Strany", value: "\(store.analysis.totalPages)", symbol: "doc.on.doc", tint: .blue)
            StatChip(title: "Neprázdne strany", value: "\(store.analysis.nonEmptyPages)", symbol: "doc.text.fill", tint: .teal)
            StatChip(title: "Listy (odhad duplex)", value: "\(store.effectiveSheetCount)", symbol: "rectangle.stack", tint: .indigo)
            StatChip(title: "Bezpečnostné prvky", value: "\(store.securityElements.count)", symbol: "shield.checkerboard", tint: .green)

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
                                set: { store.manualSheetCount = $0 }), in: 1...999)
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
                Label("Detegované bezpečnostné prvky", systemImage: "brain.head.profile")
                    .font(.headline)
                    .padding(.bottom, 2)

                if store.securityElements.isEmpty && !store.isAnalyzing {
                    Text("Nenašli sa žiadne pečiatky ani podpisy. Pridajte ich manuálne kliknutím na nástroj nižšie.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }

                ForEach(store.securityElements) { element in
                    ElementRow(element: element,
                               isSelected: selectedElementID == element.id,
                               onSelect: { selectedElementID = element.id },
                               onDelete: { store.removeSecurityElement(id: element.id) },
                               onKindChange: { kind in store.updateElementKind(id: element.id, kind: kind) },
                               onDescriptionChange: { text in store.updateElementDescription(id: element.id, text: text) })
                }

                Divider().padding(.vertical, 6)
                Text("Manuálne pridanie")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Nástroj", selection: $selectedTool) {
                    ForEach([SecurityElement.Kind.officialStamp,
                             .handwrittenSignature,
                             .embossedSeal,
                             .initial,
                             .other], id: \.self) { kind in
                        Label(kind.rawValue, systemImage: kind.sfSymbol).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    addManualElement()
                } label: {
                    Label("Pridať na stranu 1 (stred dolu)", systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.vertical, 14)
        .padding(.trailing, 14)
    }

    private func addManualElement() {
        store.addSecurityElement(
            kind: selectedTool,
            pageIndex: 0,
            rect: NormalizedRect(x: 0.55, y: 0.78, width: 0.28, height: 0.12))
    }
}

struct ElementRow: View {
    let element: SecurityElement
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onKindChange: (SecurityElement.Kind) -> Void
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

                if !element.detectedByAI {
                    Text("manuálne")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15), in: Capsule())
                } else {
                    ConfidenceBar(confidence: element.confidence)
                    Text("\(Int(element.confidence * 100)) %")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            Text("Strana \(element.pageIndex + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Slovný opis pre doložku", text: Binding(
                get: {
                    if descriptionFocused || !descriptionDraft.isEmpty {
                        return descriptionDraft
                    }
                    return element.verbalDescription
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
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
