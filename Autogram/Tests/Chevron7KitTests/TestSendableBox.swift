import Foundation

struct TestUncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) {
        self.value = value
    }
}
