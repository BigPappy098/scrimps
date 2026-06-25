import Foundation

/// Decides which cast member (if any) a transcript is addressed to, and returns
/// the note text with the leading name stripped off.
///
/// A note like "Sarah your cross is late" becomes
/// (assigned: "Sarah", note: "Your cross is late"). If no leading name matches
/// the cast, the note is for everyone (assigned: nil).
enum NameMatcher {

    static func match(transcript raw: String, cast: [CastMember]) -> (assigned: String?, note: String) {
        let transcript = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return (nil, "") }
        guard !cast.isEmpty else { return (nil, capitalizeSentence(transcript)) }

        let words = transcript.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return (nil, "") }

        // Try the longest leading phrase first (handles "Mary Beth ..." before "Mary ...").
        let maxLead = min(3, words.count)
        for leadCount in stride(from: maxLead, through: 1, by: -1) {
            let lead = words.prefix(leadCount).joined(separator: " ")
            let leadNorm = normalize(lead)
            guard !leadNorm.isEmpty else { continue }
            if let member = bestMatch(for: leadNorm, cast: cast) {
                let remainder = stripLeadingSeparators(words.dropFirst(leadCount).joined(separator: " "))
                return (member.name, capitalizeSentence(remainder))
            }
        }
        return (nil, capitalizeSentence(transcript))
    }

    /// Name variants fed to the speech engine as recognition hints.
    static func contextualVariants(_ name: String) -> [String] {
        variants(of: name)
    }

    // MARK: - Matching

    private static func bestMatch(for leadNorm: String, cast: [CastMember]) -> CastMember? {
        var best: (member: CastMember, score: Double)?
        for member in cast {
            for variant in variants(of: member.name) {
                let v = normalize(variant)
                guard !v.isEmpty else { continue }
                let distance = levenshtein(Array(leadNorm), Array(v))
                let score = similarity(leadNorm, v)
                // Accept exact matches, near-misses on longer names (handles
                // "Jon" vs "John"), or a high overall similarity.
                let accept = leadNorm == v
                    || (distance <= 1 && min(leadNorm.count, v.count) >= 3)
                    || score >= 0.85
                if accept, best == nil || score > best!.score {
                    best = (member, score)
                }
            }
        }
        return best?.member
    }

    private static func variants(of name: String) -> [String] {
        let parts = name.split(separator: " ").map(String.init)
        var result = [name]
        if let first = parts.first { result.append(first) }
        if parts.count > 1, let last = parts.last { result.append(last) }
        return result
    }

    // MARK: - Text helpers

    private static func normalize(_ string: String) -> String {
        let lowered = string.lowercased()
        let scalars = lowered.unicodeScalars.filter {
            CharacterSet.letters.contains($0) || $0 == " "
        }
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func stripLeadingSeparators(_ string: String) -> String {
        var s = Substring(string)
        while let first = s.first, first == " " || ",:;.-—".contains(first) {
            s = s.dropFirst()
        }
        return String(s).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizeSentence(_ string: String) -> String {
        guard let first = string.first else { return string }
        return first.uppercased() + string.dropFirst()
    }

    // MARK: - Fuzzy distance

    private static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        let distance = levenshtein(Array(a), Array(b))
        return 1.0 - Double(distance) / Double(maxLen)
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
