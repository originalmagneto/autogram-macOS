import SwiftUI

struct PDFDetailView: View {
    let item: PDFItem?

    var body: some View {
        if let item {
            VStack(spacing: 0) {
                if item.descriptor.isPDF {
                    PDFPreviewView(url: item.descriptor.sourceURL)
                } else {
                    ASiCContentsView(inspection: item.inspection)
                }
                ExistingSignaturesView(inspection: item.inspection)
            }
            .navigationTitle(item.descriptor.redactedDisplayName)
        } else {
            ContentUnavailableView {
                Label("No PDF Selected", systemImage: "doc.richtext")
            } description: {
                Text("Select a PDF from the sidebar to preview it.")
            }
        }
    }
}

private struct ExistingSignaturesView: View {
    let inspection: PDFItemInspection

    var body: some View {
        GroupBox("Existing Signatures") {
            switch inspection {
            case .pending:
                Text("Inspecting signatures…")
                    .foregroundStyle(.secondary)
            case .failed:
                Label("Signature inspection failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            case .completed(let document) where document.signatures.isEmpty:
                Label("No signatures found", systemImage: "signature")
                    .foregroundStyle(.secondary)
            case .completed(let document):
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(document.signatures) { signature in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(signature.signerDisplayName ?? "Unknown signer")
                                .fontWeight(.semibold)
                            Text(validationLabel(for: signature.validationState))
                                .foregroundStyle(validationColor(for: signature.validationState))
                            Text([signature.signingTime.map { $0.formatted(date: .abbreviated, time: .shortened) }, signature.format]
                                .compactMap { $0 }
                                .joined(separator: " · "))
                                .foregroundStyle(.secondary)
                            Text(signature.hasQualifiedTimestamp ? "Qualified timestamp" : "No qualified timestamp")
                                .foregroundStyle(.secondary)
                            if !signature.documents.isEmpty {
                                Text("Covers: \(signature.documents.joined(separator: ", "))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func validationLabel(for state: SignatureValidationState) -> String {
        switch state {
        case .valid: "Valid"
        case .invalid: "Invalid"
        case .indeterminate: "Validation indeterminate"
        }
    }

    private func validationColor(for state: SignatureValidationState) -> Color {
        switch state {
        case .valid: .green
        case .invalid: .red
        case .indeterminate: .orange
        }
    }
}

private struct ASiCContentsView: View {
    let inspection: PDFItemInspection

    var body: some View {
        GroupBox("ASiC-E Contents") {
            if case .completed(let document) = inspection {
                ForEach(document.documents, id: \.self) { name in
                    Label(name, systemImage: "doc")
                }
            } else {
                Text("Inspecting container contents…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
