import Foundation

struct JSONLineBuffer: Sendable {
    private var bytes: [UInt8] = []
    private let maxLineBytes: Int

    init(maxLineBytes: Int) {
        self.maxLineBytes = maxLineBytes
    }

    mutating func append(_ data: Data) throws -> [MachineEvent] {
        var events: [MachineEvent] = []
        for byte in data {
            if byte == 10 {
                if bytes.last == 13 { bytes.removeLast() }
                events.append(try MachineProtocolDecoder.decode(Data(bytes)))
                bytes.removeAll(keepingCapacity: true)
            } else {
                guard bytes.count < maxLineBytes else { throw ProtocolFailure.lineTooLarge }
                bytes.append(byte)
            }
        }
        return events
    }
}
