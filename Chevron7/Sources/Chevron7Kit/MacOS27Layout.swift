// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

public enum MacOS27Layout {
    public static let rootMinimumWidth: CGFloat = 760
    public static let canvasMinimumWidth: CGFloat = 460
    public static let inspectorMinimumWidth: CGFloat = 0
    public static let inspectorIdealWidth: CGFloat = 350
    /// ZaKo clause step: the form and the live clause preview side by side. Below
    /// both minimums plus the divider the preview steps aside instead of pushing the
    /// split view wider than its column, which clipped the window on both sides.
    public static let clauseFormMinimumWidth: CGFloat = 420
    public static let clausePreviewMinimumWidth: CGFloat = 320

    public static func showsClausePreview(availableWidth: CGFloat) -> Bool {
        availableWidth >= clauseFormMinimumWidth + clausePreviewMinimumWidth + 1
    }
}
