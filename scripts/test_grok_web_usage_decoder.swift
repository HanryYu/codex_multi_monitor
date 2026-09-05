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
        let zeroUsage = try GrokWebUsageDecoder.decode(Data(zeroBytes))
        precondition(zeroUsage.usedPercent == 0)
        precondition(zeroUsage.resetAt > 0)
        precondition(zeroUsage.periodSeconds == 7 * 24 * 60 * 60)
        print("Grok web usage decoder tests passed")
    }
}
