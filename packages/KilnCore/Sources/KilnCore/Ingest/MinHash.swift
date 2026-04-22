import Foundation

public enum MinHash {
    /// Deterministic word-shingle tokenization. Folds to lowercase and splits on
    /// non-alphanumeric runs. Returns k-gram joined by a single space.
    public static func shingles(_ text: String, size: Int) -> [String] {
        let lower = text.lowercased()
        var words: [String] = []
        var current = ""
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        guard words.count >= size else { return [] }
        var out: [String] = []
        out.reserveCapacity(words.count - size + 1)
        for i in 0...(words.count - size) {
            out.append(words[i..<(i + size)].joined(separator: " "))
        }
        return out
    }

    /// FNV-1a 64-bit hash.
    public static func fnv1a64(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h &*= 0x100000001b3
        }
        return h
    }

    /// SplitMix64 — a fast, high-quality finalizer used here for per-hash mixing.
    public static func splitmix64(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// MinHash signature: for each of `numHashes` hash functions, the minimum hash
    /// value over all shingles.
    public static func signature(shingles: [String], numHashes: Int, seed: UInt64) -> [UInt64] {
        precondition(numHashes > 0, "numHashes must be positive")
        var sig = [UInt64](repeating: .max, count: numHashes)
        if shingles.isEmpty { return sig }
        for shingle in shingles {
            let base = fnv1a64(shingle)
            for i in 0..<numHashes {
                let slot = splitmix64(UInt64(bitPattern: Int64(i)) ^ seed)
                let h = splitmix64(base ^ slot)
                if h < sig[i] { sig[i] = h }
            }
        }
        return sig
    }

    /// Estimated Jaccard similarity from two signatures of the same length.
    public static func jaccard(_ a: [UInt64], _ b: [UInt64]) -> Double {
        precondition(a.count == b.count, "signature length mismatch")
        guard !a.isEmpty else { return 0 }
        var matches = 0
        for i in a.indices where a[i] == b[i] { matches += 1 }
        return Double(matches) / Double(a.count)
    }

    /// Hash a single band (a slice of the signature) into a bucket key for LSH.
    public static func bandHash(_ sig: [UInt64], band: Int, rows: Int) -> UInt64 {
        var h: UInt64 = 0xDEADBEEFDEADBEEF
        let start = band * rows
        for i in 0..<rows {
            h = splitmix64(h ^ sig[start + i])
        }
        return h
    }
}

/// Locality-sensitive hash index for MinHash signatures.
public struct MinHashLSH: Sendable {
    public let threshold: Double
    public let numHashes: Int
    public let bands: Int
    public let rows: Int
    public let shingleSize: Int
    public let seed: UInt64

    private struct Entry { let signature: [UInt64] }
    private var entries: [Entry] = []
    private var buckets: [UInt64: [Int]] = [:]

    public init(threshold: Double, numHashes: Int, bands: Int, shingleSize: Int, seed: UInt64) {
        precondition(numHashes % bands == 0, "numHashes must be divisible by bands")
        self.threshold = threshold
        self.numHashes = numHashes
        self.bands = bands
        self.rows = numHashes / bands
        self.shingleSize = shingleSize
        self.seed = seed
    }

    public var count: Int { entries.count }

    /// Insert `text` if no near-duplicate exists. Returns true if novel, false if duplicate.
    /// Text with fewer words than `shingleSize` is always treated as novel (no shingles to
    /// form a meaningful signature — exact dedup handles that regime).
    @discardableResult
    public mutating func add(_ text: String) -> Bool {
        let shingles = MinHash.shingles(text, size: shingleSize)
        if shingles.isEmpty { return true }
        let sig = MinHash.signature(shingles: shingles, numHashes: numHashes, seed: seed)

        var candidates = Set<Int>()
        for b in 0..<bands {
            let bh = MinHash.bandHash(sig, band: b, rows: rows)
            if let hits = buckets[bh] {
                for idx in hits { candidates.insert(idx) }
            }
        }
        for idx in candidates {
            let jac = MinHash.jaccard(sig, entries[idx].signature)
            if jac >= threshold { return false }
        }

        let newIdx = entries.count
        entries.append(Entry(signature: sig))
        for b in 0..<bands {
            let bh = MinHash.bandHash(sig, band: b, rows: rows)
            buckets[bh, default: []].append(newIdx)
        }
        return true
    }
}
