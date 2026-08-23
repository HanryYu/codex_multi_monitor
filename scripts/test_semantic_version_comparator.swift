import Foundation

@main
enum SemanticVersionComparatorTests {
    static func main() {
        precondition(SemanticVersionComparator.compare("0.7.9", "0.7.8") == .orderedDescending)
        precondition(SemanticVersionComparator.compare("v0.7.10", "0.7.9") == .orderedDescending)
        precondition(SemanticVersionComparator.compare("0.7.9", "0.7.9") == .orderedSame)
        precondition(SemanticVersionComparator.compare("0.7.9-beta", "0.7.9") == .orderedSame)
        precondition(SemanticVersionComparator.compare("0.6.15", "0.7.0") == .orderedAscending)
        print("Semantic version comparator tests passed")
    }
}
