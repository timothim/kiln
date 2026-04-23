import Foundation

public enum DatasetSplit {
    public static func split(
        _ examples: [ChatMLExample],
        evalFraction: Double,
        seed: UInt64
    ) -> (train: [ChatMLExample], eval: [ChatMLExample]) {
        precondition(
            evalFraction >= 0.0 && evalFraction <= 1.0,
            "evalFraction must be in [0, 1]"
        )

        if examples.isEmpty {
            return ([], [])
        }

        var groups: [String: [ChatMLExample]] = [:]
        var order: [String] = []
        for ex in examples {
            if groups[ex.sourcePath] == nil {
                order.append(ex.sourcePath)
            }
            groups[ex.sourcePath, default: []].append(ex)
        }

        var keys = order.sorted()

        var prng = SeededRNG(seed: seed)
        for i in stride(from: keys.count - 1, to: 0, by: -1) {
            let j = Int(prng.next() % UInt64(i + 1))
            keys.swapAt(i, j)
        }

        var evalFileCount = Int((Double(keys.count) * evalFraction).rounded())
        if evalFileCount == 0 && evalFraction > 0 && keys.count >= 2 {
            evalFileCount = 1
        }
        evalFileCount = min(max(evalFileCount, 0), max(keys.count - 1, 0))

        let evalKeys = Set(keys.prefix(evalFileCount))

        var train: [ChatMLExample] = []
        var eval: [ChatMLExample] = []
        for key in order {
            let group = groups[key] ?? []
            if evalKeys.contains(key) {
                eval.append(contentsOf: group)
            } else {
                train.append(contentsOf: group)
            }
        }
        return (train, eval)
    }
}

struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
