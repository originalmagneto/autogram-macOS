import Foundation

public struct ASiCEPackager: Sendable {
    public struct Entry: Sendable {
        public var path: String
        public var data: Data
        public var storeUncompressed: Bool

        public init(path: String, data: Data, storeUncompressed: Bool = false) {
            self.path = path
            self.data = data
            self.storeUncompressed = storeUncompressed
        }
    }

    public init() {}

    public func package(files: [Entry]) throws -> Data {
        var out = Data()
        var centralRecords: [Data] = []
        var offset: UInt32 = 0

        let sorted = files.sorted { lhs, rhs in
            if lhs.path == "mimetype" { return true }
            if rhs.path == "mimetype" { return false }
            return lhs.path < rhs.path
        }

        for entry in sorted {
            let nameBytes = Data(entry.path.utf8)
            let crc = CRC32.of(entry.data)
            let localHeaderOffset = offset

            var header = Data()
            header.appendLE(UInt32(0x04034b50))
            header.appendLE(UInt16(20))
            header.appendLE(UInt16(0))
            header.appendLE(UInt16(0))
            header.appendLE(dosTime)
            header.appendLE(dosDate)
            header.appendLE(UInt32(crc))
            header.appendLE(UInt32(entry.data.count))
            header.appendLE(UInt32(entry.data.count))
            header.appendLE(UInt16(nameBytes.count))
            header.appendLE(UInt16(0))
            out.append(header)
            out.append(nameBytes)
            out.append(entry.data)

            var central = Data()
            central.appendLE(UInt32(0x02014b50))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(dosTime)
            central.appendLE(dosDate)
            central.appendLE(UInt32(crc))
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt16(nameBytes.count))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt32(0))
            central.appendLE(UInt32(localHeaderOffset))
            central.append(nameBytes)
            centralRecords.append(central)

            offset += UInt32(header.count + nameBytes.count + entry.data.count)
        }

        let centralStart = offset
        for record in centralRecords { out.append(record) }
        let centralSize = UInt32(out.count) - centralStart

        out.appendLE(UInt32(0x06054b50))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(sorted.count))
        out.appendLE(UInt16(sorted.count))
        out.appendLE(UInt32(centralSize))
        out.appendLE(UInt32(centralStart))
        out.appendLE(UInt16(0))

        return out
    }

    private var dosTime: UInt16 {
        let calendar = Calendar.current
        let hour = UInt16(calendar.component(.hour, from: Date()))
        let minute = UInt16(calendar.component(.minute, from: Date()))
        let second = UInt16(calendar.component(.second, from: Date()) / 2)
        return (hour << 11) | (minute << 5) | second
    }

    private var dosDate: UInt16 {
        let calendar = Calendar.current
        let year = UInt16(max(calendar.component(.year, from: Date()) - 1980, 0))
        let month = UInt16(calendar.component(.month, from: Date()))
        let day = UInt16(calendar.component(.day, from: Date()))
        return (year << 9) | (month << 5) | day
    }
}

public enum CRC32 {
    static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    public static func of(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }
    mutating func appendLE(_ value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }
}
