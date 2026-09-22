// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Kit
import Chevron7TestSupport
import XCTest
@testable import Chevron7App

extension XCTestCase {
    /// An `AppSettingsStore` whose evidence register, vision bank, output, templates and
    /// signature images live in a temporary folder removed when the test ends, never in
    /// the user's real `~/Library/Application Support/Chevron7`.
    @MainActor
    func makeSettingsStore(ezzkAccountController: EZZKAccountController? = nil) -> AppSettingsStore {
        AppSettingsStore(ezzkAccountController: ezzkAccountController,
                         storageRoot: makeTemporaryDirectory("app-storage"))
    }
}
