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
        case rpcStatus(Int)
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> GrokWebUsagePayload {
        guard !data.isEmpty, data.count <= 2_000_000 else { throw DecodeError.invalidFrame }
        let payload = try protobufPayload(data)
        var root = ProtoReader(data: payload)
        var config: Data?
        while let field = try root.nextField() {
            if field.number == 1, field.wireType == 2 {
                guard config == nil else { throw DecodeError.invalidFrame }
                config = try root.readLengthDelimited()
            } else { try root.skip(wireType: field.wireType) }
        }
        guard let config else { throw DecodeError.missingUsage }
        var reader = ProtoReader(data: config)
        var percent: Double?
        var periodType = 2
        var hasPeriod = false
        var periodStart = 0
        var periodEnd = 0
        var resetAt = 0
        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, 5):
                let value = Double(Float(bitPattern: try reader.readFixed32()))
                guard value.isFinite, value >= 0 else { throw DecodeError.invalidFrame }
                percent = value
            case (5, 2):
                resetAt = try ProtoReader.timestampSeconds(from: reader.readLengthDelimited())
            case (8, 2):
                var period = ProtoReader(data: try reader.readLengthDelimited())
                while let nested = try period.nextField() {
                    switch (nested.number, nested.wireType) {
                    case (1, 0):
                        let value = try period.readVarint()
                        guard value == 1 || value == 2 else { throw DecodeError.invalidFrame }
                        periodType = Int(value)
                        hasPeriod = true
                    case (2, 2): periodStart = try ProtoReader.timestampSeconds(from: period.readLengthDelimited())
                    case (3, 2): periodEnd = try ProtoReader.timestampSeconds(from: period.readLengthDelimited())
                    default: try period.skip(wireType: nested.wireType)
                    }
                }
            default: try reader.skip(wireType: field.wireType)
            }
        }
        if periodEnd > 0 { resetAt = periodEnd }
        // Only an active, complete current period confirms omitted proto3 scalar = zero.
        // A reset date or historical billing metadata alone is not current quota.
        if percent == nil, hasPeriod, periodStart > 0,
           Double(periodStart) <= now.timeIntervalSince1970,
           Double(periodEnd) > now.timeIntervalSince1970 {
            percent = 0
        }
        guard let percent else { throw DecodeError.missingUsage }
        return GrokWebUsagePayload(usedPercent: percent, resetAt: resetAt,
                                  periodSeconds: (periodType == 2 ? 7 : 30) * 24 * 60 * 60)
    }

    private static func protobufPayload(_ data: Data) throws -> Data {
        // New deployments return an unframed protobuf message from this same endpoint.
        if data[0] != 0 && data[0] != 0x80 { return data }
        var index = 0
        var payload: Data?
        var sawTrailers = false
        while index < data.count {
            guard !sawTrailers, data.count - index >= 5 else { throw DecodeError.invalidFrame }
            let flags = data[index]
            let length = Int(data[index + 1]) << 24 | Int(data[index + 2]) << 16
                | Int(data[index + 3]) << 8 | Int(data[index + 4])
            index += 5
            guard length <= data.count - index else { throw DecodeError.invalidFrame }
            let frame = data.subdata(in: index..<(index + length))
            index += length
            switch flags {
            case 0:
                guard payload == nil, !frame.isEmpty else { throw DecodeError.invalidFrame }
                payload = frame
            case 0x80:
                sawTrailers = true
                guard let text = String(data: frame, encoding: .utf8) else { throw DecodeError.invalidFrame }
                for line in text.components(separatedBy: "\r\n") {
                    let pair = line.split(separator: ":", maxSplits: 1)
                    if pair.count == 2, pair[0].lowercased() == "grpc-status" {
                        guard let code = Int(pair[1].trimmingCharacters(in: .whitespaces)), code >= 0 else {
                            throw DecodeError.invalidFrame
                        }
                        if code != 0 { throw DecodeError.rpcStatus(code) }
                    }
                }
            default: throw DecodeError.invalidFrame
            }
        }
        guard let payload else { throw DecodeError.missingUsage }
        return payload
    }
}

private struct ProtoReader {
    let data: Data
    var index = 0

    mutating func nextField() throws -> (number: Int, wireType: Int)? {
        guard index < data.count else { return nil }
        let key = try readVarint()
        guard key >> 3 > 0, key >> 3 <= 0x1fff_ffff else { throw GrokWebUsageDecoder.DecodeError.invalidFrame }
        return (Int(key >> 3), Int(key & 7))
    }

    mutating func readVarint() throws -> UInt64 {
        var value: UInt64 = 0
        for offset in 0..<10 {
            guard index < data.count else { throw GrokWebUsageDecoder.DecodeError.invalidFrame }
            let byte = data[index]
            index += 1
            guard offset != 9 || byte <= 1 else { throw GrokWebUsageDecoder.DecodeError.invalidFrame }
            value |= UInt64(byte & 0x7f) << (offset * 7)
            if byte & 0x80 == 0 { return value }
        }
        throw GrokWebUsageDecoder.DecodeError.invalidFrame
    }

    mutating func readFixed32() throws -> UInt32 {
        guard data.count - index >= 4 else { throw GrokWebUsageDecoder.DecodeError.invalidFrame }
        defer { index += 4 }
        return UInt32(data[index]) | UInt32(data[index + 1]) << 8
            | UInt32(data[index + 2]) << 16 | UInt32(data[index + 3]) << 24
    }

    mutating func readLengthDelimited() throws -> Data {
        let length = try readVarint()
        guard length <= UInt64(data.count - index) else { throw GrokWebUsageDecoder.DecodeError.invalidFrame }
        defer { index += Int(length) }
        return data.subdata(in: index..<(index + Int(length)))
    }

    mutating func skip(wireType: Int) throws {
        switch wireType {
        case 0: _ = try readVarint()
        case 1, 5:
            let count = wireType == 1 ? 8 : 4
            guard data.count - index >= count else { throw GrokWebUsageDecoder.DecodeError.invalidFrame }
            index += count
        case 2: _ = try readLengthDelimited()
        default: throw GrokWebUsageDecoder.DecodeError.invalidFrame
        }
    }

    static func timestampSeconds(from data: Data) throws -> Int {
        var reader = ProtoReader(data: data)
        var seconds = 0
        while let field = try reader.nextField() {
            if field.number == 1, field.wireType == 0 {
                let value = try reader.readVarint()
                guard value < UInt64(Int.max) else { throw GrokWebUsageDecoder.DecodeError.invalidFrame }
                seconds = Int(value)
            } else { try reader.skip(wireType: field.wireType) }
        }
        return seconds
    }
}
