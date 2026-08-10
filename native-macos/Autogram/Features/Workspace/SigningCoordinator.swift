import Foundation

actor SigningCoordinator {
    private let engine: any SigningEngine
    private let workspace: WorkspaceModel?

    private(set) var state: SessionState = .idle
    private var signableInspectionIDs: Set<String> = []

    init(engine: any SigningEngine, workspace: WorkspaceModel? = nil) {
        self.engine = engine
        self.workspace = workspace
    }

    func inspect(_ files: [PDFItemDescriptor]) async throws {
        guard state == .idle else { throw SigningFailure.invalidTransition }

        state = .inspectingFiles
        await updateWorkspaceActivity(.inspectingDocuments)
        do {
            let inspections = try await engine.inspect(files: files)
            guard hasCompletedSignableInspection(for: files, in: inspections) else {
                throw SigningFailure.engine("Document inspection did not produce a signable result for every requested file.")
            }

            await updateWorkspace(inspections, for: files)
            await updateWorkspace(files.map(\.id), to: .inspected)
            signableInspectionIDs = Set(files.map(\.id))
            state = .awaitingPIN
            await updateWorkspaceActivity(nil)
        } catch {
            state = .failed(asSigningFailure(error))
            await updateWorkspaceInspectionFailure(for: files.map(\.id))
            await updateWorkspaceActivity(nil)
            throw error
        }
    }

    func seedCompletedInspection(for files: [PDFItemDescriptor]) async throws {
        guard state == .idle, !files.isEmpty else { throw SigningFailure.invalidTransition }

        signableInspectionIDs = Set(files.map(\.id))
        state = .awaitingPIN
        await updateWorkspace(files.map(\.id), to: .inspected)
    }

    func beginSigning(request: SigningRequest) async throws {
        let requestedFileIDs = Set(request.files.map(\.id))
        guard state == .awaitingPIN,
              !requestedFileIDs.isEmpty,
              requestedFileIDs.isSubset(of: signableInspectionIDs) else {
            throw SigningFailure.invalidTransition
        }

        state = .signing(progress: BatchProgress(total: request.files.count))
        await updateWorkspaceActivity(.preparingSignatures)
        var succeeded = 0
        var failed = 0
        var firstFailure: SigningFailure?
        var completedOutputs: [PDFItemDescriptor] = []

        do {
            for try await event in engine.sign(request: request) {
                switch event {
                case .started:
                    break
                case .activity(let phase):
                    await updateWorkspaceActivity(phase)
                case .fileSigning(let fileID):
                    await updateWorkspace([fileID], to: .signing)
                case .completed(let fileID, let outputURL):
                    succeeded += 1
                    completedOutputs.append(PDFItemDescriptor(id: fileID, sourceURL: outputURL))
                    await updateWorkspaceOutput(for: fileID, to: outputURL)
                    await updateWorkspace([fileID], to: .completed)
                    state = .signing(progress: BatchProgress(total: request.files.count, completed: succeeded, failed: failed))
                case .failed(let fileID, let failure):
                    failed += 1
                    firstFailure = firstFailure ?? failure
                    await updateWorkspace([fileID], to: .failed)
                    state = .signing(progress: BatchProgress(total: request.files.count, completed: succeeded, failed: failed))
                case .cancelled:
                    state = .cancelled
                    await updateWorkspaceActivity(nil)
                    return
                }
            }
        } catch {
            let failure = asSigningFailure(error)
            state = .failed(failure)
            await updateWorkspaceActivity(nil)
            throw failure
        }

        await inspectCompletedOutputs(completedOutputs)

        let summary = BatchSummary(succeeded: succeeded, failed: failed)
        if failed == 0 {
            state = .completed(summary)
        } else if succeeded > 0 {
            state = .partiallyCompleted(summary)
        } else {
            let failure = firstFailure ?? .fileFailed(request.files.first?.id ?? "")
            state = .failed(failure)
            await updateWorkspaceActivity(nil)
            throw failure
        }
        await updateWorkspaceActivity(nil)
    }

    func cancel() async throws {
        guard case .signing = state else { throw SigningFailure.invalidTransition }

        await engine.cancel()
        state = .cancelled
        await updateWorkspaceActivity(nil)
    }

    private func updateWorkspace(_ fileIDs: [String], to status: PDFItemStatus) async {
        guard let workspace else { return }
        for fileID in fileIDs {
            await workspace.updateStatus(for: fileID, to: status)
        }
    }

    private func updateWorkspace(_ inspections: [PDFInspection], for files: [PDFItemDescriptor]) async {
        guard let workspace else { return }
        await workspace.applyInspectionResults(inspections, for: files)
    }

    private func updateWorkspaceOutput(for fileID: String, to outputURL: URL) async {
        guard let workspace else { return }
        await workspace.updateSignedOutput(for: fileID, to: outputURL)
    }

    private func inspectCompletedOutputs(_ files: [PDFItemDescriptor]) async {
        guard !files.isEmpty else { return }
        await updateWorkspaceActivity(.inspectingDocuments)
        do {
            let inspections = try await engine.inspect(files: files)
            guard let workspace else { return }
            await workspace.applyPostSigningInspectionResults(inspections, for: files)
        } catch {
            guard let workspace else { return }
            await workspace.markPostSigningInspectionFailed(for: files.map(\.id))
        }
    }

    private func updateWorkspaceInspectionFailure(for fileIDs: [String]) async {
        guard let workspace else { return }
        await workspace.markInspectionFailed(for: fileIDs)
    }

    private func updateWorkspaceActivity(_ phase: SigningActivityPhase?) async {
        guard let workspace else { return }
        await workspace.setSigningActivityPhase(phase)
    }

    private func asSigningFailure(_ error: Error) -> SigningFailure {
        if let failure = error as? SigningFailure {
            return failure
        }
        if let failure = error as? CLIProcessFailure {
            return .engine(failure.localizedDescription)
        }
        return .engine("Signing engine failed")
    }

    private func hasCompletedSignableInspection(
        for files: [PDFItemDescriptor],
        in inspections: [PDFInspection]
    ) -> Bool {
        let resultsByID = Dictionary(
            inspections.flatMap(\.files).map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        return files.allSatisfy { resultsByID[$0.id]?.isSignable == true }
    }
}
