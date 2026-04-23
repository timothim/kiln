import Foundation

public struct ExactDedup: Sendable {
    private var hashes: Set<String> = []

    public init() {}

    public var count: Int { hashes.count }

    /// Returns true if novel, false if duplicate.
    @discardableResult
    public mutating func add(_ text: String) -> Bool {
        let h = TextNormalization.canonicalHash(text)
        return hashes.insert(h).inserted
    }
}
