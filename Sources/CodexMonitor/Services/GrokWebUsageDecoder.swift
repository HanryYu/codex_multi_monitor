import Foundation

struct GrokWebUsagePayload {
    let usedPercent: Double
    let resetAt: Int
    let periodSeconds: Int
}

enum GrokWebUsageDecoder {
    enum DecodeError: Error {
        case invalidFrame
        case missingUsage
    }

    static func decode(_ data: Data) throws -> GrokWebUsagePayload {
        guard data.count >= 5, data[0] == 0 else { throw DecodeError.invalidFrame }
        let length = Int(data[1]) << 24 | Int(data[2]) << 16 | Int(data[3]) << 8 | Int(data[4])
        guard length > 0, data.count >= 5 + length else { throw DecodeError.invalidFrame }
        var root = ProtoReader(data: data.subdata(in: 5..<(5 + length)))
        guard let config = root.lengthDelimited(field: 1) else { throw DecodeError.invalidFrame }
        var reader = ProtoReader(data: config)

        var usedPercent: Double?
        var periodType = 2
        var resetAt = 0

        while let field = reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, 5):
                usedPercent = Double(Float(bitPattern: reader.readFixed32()))
            case (5, 2):
                if let timestamp = reader.readLengthDelimited() {
                    resetAt = ProtoReader.timestampSeconds(from: timestamp)
                }
            case (8, 2):
                if let periodData = reader.readLengthDelimited() {
                    var period = ProtoReader(data: periodData)
                    while let nested = period.nextField() {
                        if nested.number == 1, nested.wireType == 0 {
                            periodType = Int(period.readVarint())
                        } else if nested.number == 3, nested.wireType == 2,
                                  let timestamp = period.readLengthDelimited() {
                            resetAt = ProtoReader.timestampSeconds(from: timestamp)
                        } else {
                            period.skip(wireType: nested.wireType)
                        }
                    }
                }
            default:
                reader.skip(wireType: field.wireType)
            }
        }

        guard let usedPercent else { throw DecodeError.missingUsage }
        let seconds = periodType == 2 ? 7 * 24 * 60 * 60 : 30 * 24 * 60 * 60
        return GrokWebUsagePayload(usedPercent: usedPercent, resetAt: resetAt, periodSeconds: seconds)
    }
}

private struct ProtoReader {
    let data: Data
    var index = 0

    mutating func nextField() -> (number: Int, wireType: Int)? {
        guard index < data.count else { return nil }
        let key = readVarint()
        return (Int(key >> 3), Int(key & 0x7))
    }

    mutating func readVarint() -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.count, shift < 64 {
            let byte = data[index]
            index += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return value
    }

    mutating func readFixed32() -> UInt32 {
        guard index + 4 <= data.count else { index = data.count; return 0 }
        defer { index += 4 }
        return UInt32(data[index])
            | UInt32(data[index + 1]) << 8
            | UInt32(data[index + 2]) << 16
            | UInt32(data[index + 3]) << 24
    }

    mutating func readLengthDelimited() -> Data? {
        let length = Int(readVarint())
        guard length >= 0, index + length <= data.count else { index = data.count; return nil }
        defer { index += length }
        return data.subdata(in: index..<(index + length))
    }

    mutating func lengthDelimited(field target: Int) -> Data? {
        while let field = nextField() {
            if field.number == target, field.wireType == 2 { return readLengthDelimited() }
            skip(wireType: field.wireType)
        }
        return nil
    }

    mutating func skip(wireType: Int) {
        switch wireType {
        case 0: _ = readVarint()
        case 1: index = min(data.count, index + 8)
        case 2:
            let length = Int(readVarint())
            index = min(data.count, index + max(0, length))
        case 5: index = min(data.count, index + 4)
        default: index = data.count
        }
    }

    static func timestampSeconds(from data: Data) -> Int {
        var reader = ProtoReader(data: data)
        while let field = reader.nextField() {
            if field.number == 1, field.wireType == 0 { return Int(reader.readVarint()) }
            reader.skip(wireType: field.wireType)
        }
        return 0
    }
}
