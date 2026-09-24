// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Kit

extension SecurityElement {
    /// What the delete action (row button or the Delete key) does with this element.
    enum DeleteAction: Equatable {
        /// A rejected finding is a negative training example; nothing deletes it.
        case none
        /// A pending AI suggestion is rejected, so the detector learns from the mistake.
        case reject
        /// A hand-drawn element, or an AI finding already confirmed, is removed (undo restores it).
        case remove
    }

    /// Rejected findings are locked: no geometry, kind, page or description change,
    /// no duplicate or refine. Only "Vrátiť na kontrolu" returns them to review.
    var isLockedByRejection: Bool { reviewState == .rejected }

    var deleteAction: DeleteAction {
        if isLockedByRejection { return .none }
        return detectedByAI && reviewState == .pending ? .reject : .remove
    }
}
