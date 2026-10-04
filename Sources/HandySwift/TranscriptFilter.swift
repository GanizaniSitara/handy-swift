import Foundation

/// Removes filler words and collapses stutters. Port of Handy.NET's TranscriptFilter, itself a
/// port of upstream Handy's audio_toolkit/text.rs:filter_transcription_output.
enum TranscriptFilter {
    // Each locale opts in independently: Portuguese "um" means "a", Spanish "ha" is a verb.
    private static let byLang: [String: [String]] = [
        "en": ["uh", "um", "uhm", "umm", "uhh", "uhhh", "ah", "hmm", "hm", "mmm", "mm", "mh", "eh", "ehh", "ha"],
        "es": ["ehm", "mmm", "hmm", "hm"],
        "pt": ["ahm", "hmm", "mmm", "hm"],
        "fr": ["euh", "hmm", "hm", "mmm"],
        "de": ["äh", "ähm", "hmm", "hm", "mmm"],
        "it": ["ehm", "hmm", "mmm", "hm"],
        "cs": ["ehm", "hmm", "mmm", "hm"],
        "pl": ["hmm", "mmm", "hm"],
        "tr": ["hmm", "mmm", "hm"],
        "ru": ["хм", "ммм", "hmm", "mmm"],
        "uk": ["хм", "ммм", "hmm", "mmm"],
        "ar": ["hmm", "mmm"],
        "ja": ["hmm", "mmm"],
        "ko": ["hmm", "mmm"],
        "vi": ["hmm", "mmm", "hm"],
        "zh": ["hmm", "mmm"],
    ]

    // No "um", "eh", "ha": real words in several languages.
    private static let fallback = ["uh", "uhm", "umm", "uhh", "uhhh", "ah", "hmm", "hm", "mmm", "mm", "mh", "ehh"]

    static func fillers(for lang: String) -> [String] {
        let base = lang.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return byLang[base.lowercased()] ?? fallback
    }

    static func filter(_ text: String, lang: String, customFillerWords: [String]?) -> String {
        var out = text
        for w in customFillerWords ?? fillers(for: lang) where !w.isEmpty {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: w))\\b[,.]?"
            out = out.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        out = collapseStutters(out)
        out = out.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 3+ consecutive repeats of the same alphabetic word become one ("wh wh wh" → "wh").
    private static func collapseStutters(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\n" }).map(String.init)
        var result: [String] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            if w.allSatisfy(\.isLetter) {
                let lower = w.lowercased()
                var count = 1
                while i + count < words.count, words[i + count].lowercased() == lower { count += 1 }
                result.append(w)
                i += count >= 3 ? count : 1
            } else {
                result.append(w)
                i += 1
            }
        }
        return result.joined(separator: " ")
    }
}
