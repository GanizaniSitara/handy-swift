import Foundation

/// An explicit phrase correction with optional context gates. Same JSON shape and semantics as
/// Handy.NET's DomainCorrection / DomainCorrectionService.
struct DomainCorrection: Codable {
    var enabled = true
    /// Legacy single-variant field; used when `variants` is empty.
    var from = ""
    var to = ""
    var variants: [String] = []
    /// At least one must appear near the match; empty means ungated.
    var requiredContext: [String] = []
    /// If any appears near the match, the rule is skipped.
    var blockedContext: [String] = []
    var caseSensitive = false
    var notes = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
        variants = try c.decodeIfPresent([String].self, forKey: .variants) ?? []
        requiredContext = try c.decodeIfPresent([String].self, forKey: .requiredContext) ?? []
        blockedContext = try c.decodeIfPresent([String].self, forKey: .blockedContext) ?? []
        caseSensitive = try c.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    var effectiveVariants: [String] {
        let v = variants.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !v.isEmpty { return v }
        let f = from.trimmingCharacters(in: .whitespaces)
        return f.isEmpty ? [] : [f]
    }
}

enum DomainCorrector {
    private static let boundary = "\\p{L}\\p{N}_'\\-"
    private static let contextWindow = 96

    struct Applied { let from: String, to: String, count: Int }

    /// Returns corrected text plus each variant that fired, for the log.
    static func apply(_ text: String, _ corrections: [DomainCorrection]) -> (text: String, applied: [Applied]) {
        var output = text
        var applied: [Applied] = []

        for c in corrections where c.enabled {
            let to = c.to.trimmingCharacters(in: .whitespaces)
            guard !to.isEmpty else { continue }
            for from in c.effectiveVariants {
                guard let regex = phraseRegex(from, caseSensitive: c.caseSensitive) else { continue }
                // Matches are evaluated against the text as it was before this variant's pass,
                // then replaced back-to-front so earlier ranges stay valid.
                let ns = output as NSString
                var count = 0
                for m in regex.matches(in: output, range: NSRange(location: 0, length: ns.length)).reversed() {
                    let start = max(0, m.range.location - contextWindow)
                    let end = min(ns.length, m.range.location + m.range.length + contextWindow)
                    let context = ns.substring(with: NSRange(location: start, length: end - start))
                    guard contextAllows(context, c) else { continue }
                    output = (output as NSString).replacingCharacters(in: m.range, with: to)
                    count += 1
                }
                if count > 0 { applied.append(Applied(from: from, to: to, count: count)) }
            }
        }
        return (output, applied)
    }

    private static func contextAllows(_ context: String, _ c: DomainCorrection) -> Bool {
        if firstMatch(context, c.blockedContext, c.caseSensitive) { return false }
        let required = c.requiredContext.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return required.isEmpty || firstMatch(context, required, c.caseSensitive)
    }

    private static func firstMatch(_ context: String, _ phrases: [String], _ caseSensitive: Bool) -> Bool {
        phrases.contains { p in
            let t = p.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, let r = phraseRegex(t, caseSensitive: caseSensitive) else { return false }
            return r.firstMatch(in: context, range: NSRange(location: 0, length: (context as NSString).length)) != nil
        }
    }

    private static func phraseRegex(_ phrase: String, caseSensitive: Bool) -> NSRegularExpression? {
        let body = phrase.split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "\\s+")
        guard !body.isEmpty else { return nil }
        return try? NSRegularExpression(
            pattern: "(?<![\(boundary)])\(body)(?![\(boundary)])",
            options: caseSensitive ? [] : [.caseInsensitive])
    }
}
