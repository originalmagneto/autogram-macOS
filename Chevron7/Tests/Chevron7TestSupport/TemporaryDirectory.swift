// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest

extension XCTestCase {
    /// A fresh, empty directory under the system temporary folder, removed when the test ends.
    public func makeTemporaryDirectory(_ label: String = "test") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chevron7-\(label)-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            XCTFail("Could not create a temporary directory: \(error)")
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
