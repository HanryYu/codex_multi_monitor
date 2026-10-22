import Foundation

@main
struct GrokWebUsageDecoderTest {
    static func main() throws {
        let hex = "00000000560a540d00005c4212001a00220c08c5f2bcd2061090bdaeb5012a0c08c5e7e1d2061090bdaeb5013a0708011500005c42421e0802120c08c5f2bcd2061090bdaeb5011a0c08c5e7e1d2061090bdaeb501580162006801800000000f677270632d7374617475733a300d0a"
        let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { offset -> UInt8? in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)
        }
        let usage = try GrokWebUsageDecoder.decode(Data(bytes))
        print("decoded percent=\(usage.usedPercent) reset=\(usage.resetAt) period=\(usage.periodSeconds)")
        precondition(Int(usage.usedPercent) == 55)
        // The fixture is a weekly usage response captured from grok.com.
        precondition(usage.resetAt > 0)
        precondition(usage.periodSeconds == 7 * 24 * 60 * 60)

        let zeroPercentHex = "00000000510a4f12001a00220c08c5f2bcd2061090bdaeb5012a0c08c5e7e1d2061090bdaeb5013a0708011500005c42421e0802120c08c5f2bcd2061090bdaeb5011a0c08c5e7e1d2061090bdaeb501580162006801800000000f677270632d7374617475733a300d0a"
        let zeroBytes = stride(from: 0, to: zeroPercentHex.count, by: 2).compactMap { offset -> UInt8? in
            let start = zeroPercentHex.index(zeroPercentHex.startIndex, offsetBy: offset)
            let end = zeroPercentHex.index(start, offsetBy: 2)
            return UInt8(zeroPercentHex[start..<end], radix: 16)
        }
        let zeroUsage = try GrokWebUsageDecoder.decode(Data(zeroBytes), now: Date(timeIntervalSince1970: Double(usage.resetAt - 3600)))
        precondition(zeroUsage.usedPercent == 0)
        precondition(zeroUsage.resetAt > 0)
        precondition(zeroUsage.periodSeconds == 7 * 24 * 60 * 60)
        // The same endpoint also returns raw protobuf (no 5-byte gRPC frame).
        let raw = Data(bytes[5..<(5 + 86)])
        let rawUsage = try GrokWebUsageDecoder.decode(raw)
        precondition(rawUsage.usedPercent == usage.usedPercent)
        precondition(rawUsage.resetAt == usage.resetAt)

        func rejects(_ data: Data) {
            do { _ = try GrokWebUsageDecoder.decode(data); preconditionFailure("Malformed data must be rejected") }
            catch { }
        }
        func frame(_ flag: UInt8, _ body: Data) -> Data {
            let n = body.count
            return Data([flag, UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)]) + body
        }
        // A successful data frame followed by an authentication-error trailer is NOT success.
        let unauthenticated = frame(0, raw) + frame(0x80, Data("grpc-status:16\r\n".utf8))
        do { _ = try GrokWebUsageDecoder.decode(unauthenticated); preconditionFailure("Trailer must win") }
        catch GrokWebUsageDecoder.DecodeError.rpcStatus(let code) { precondition(code == 16) }
        let unavailable = frame(0x80, Data("grpc-status:14\r\n".utf8))
        do { _ = try GrokWebUsageDecoder.decode(unavailable); preconditionFailure("Trailer-only error must be classified") }
        catch GrokWebUsageDecoder.DecodeError.rpcStatus(let code) { precondition(code == 14) }
        rejects(Data(bytes.dropLast()))
        rejects(frame(0, raw) + Data([0]))
        rejects(Data([0, 255, 255, 255, 255]))
        rejects(Data([10, 255, 255, 255, 255, 255, 255, 255, 255, 255, 127]))
        rejects(Data([10, 1, 13])) // truncated fixed32
        rejects(Data([10, 5, 13, 0, 0, 192, 127])) // NaN
        rejects(Data([10, 5, 13, 0, 0, 128, 127])) // infinity
        rejects(Data([10, 5, 13, 0, 0, 128, 191])) // negative
        rejects(Data("<html>login</html>".utf8))
        rejects(Data(zeroBytes)) // historic window does not prove current 0% usage
        print("Grok web usage decoder tests passed")
    }
}
