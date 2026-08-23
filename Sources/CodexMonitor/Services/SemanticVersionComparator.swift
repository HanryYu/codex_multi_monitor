import Foundation

enum SemanticVersionComparator {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        let core = version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: "-")
            .first ?? ""
        return core
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}
