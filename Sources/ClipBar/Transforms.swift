import Foundation

enum TextTransform: String, CaseIterable, Identifiable {
    case uppercase = "UPPERCASE"
    case lowercase = "lowercase"
    case capitalized = "Capitalize Words"
    case trimmed = "Trim Whitespace"
    case removeEmptyLines = "Remove Empty Lines"
    case sortLines = "Sort Lines"
    case uniqueLines = "Remove Duplicate Lines"
    case joinLines = "Join Lines"
    case prettyJSON = "Format JSON"
    case minifyJSON = "Minify JSON"
    case base64Encode = "Base64 Encode"
    case base64Decode = "Base64 Decode"
    case urlEncode = "URL Encode"
    case urlDecode = "URL Decode"

    var id: Self { self }

    static let groups: [[TextTransform]] = [
        [.uppercase, .lowercase, .capitalized],
        [.trimmed, .removeEmptyLines, .sortLines, .uniqueLines, .joinLines],
        [.prettyJSON, .minifyJSON],
        [.base64Encode, .base64Decode, .urlEncode, .urlDecode],
    ]

    private static let urlUnreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Returns nil when the input isn't valid for the transform (e.g. malformed JSON).
    func apply(_ text: String) -> String? {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        switch self {
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .capitalized: return text.capitalized
        case .trimmed:
            return lines.map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .removeEmptyLines:
            return lines.filter { $0.contains { !$0.isWhitespace } }.joined(separator: "\n")
        case .sortLines:
            return lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
        case .uniqueLines:
            var seen = Set<Substring>()
            return lines.filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .joinLines:
            return lines.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .prettyJSON: return Self.json(text, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        case .minifyJSON: return Self.json(text, options: [.withoutEscapingSlashes])
        case .base64Encode: return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters)
                .flatMap { String(data: $0, encoding: .utf8) }
        case .urlEncode: return text.addingPercentEncoding(withAllowedCharacters: Self.urlUnreserved)
        case .urlDecode: return text.removingPercentEncoding
        }
    }

    private static func json(_ text: String, options: JSONSerialization.WritingOptions) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed),
              let data = try? JSONSerialization.data(withJSONObject: object, options: options.union(.fragmentsAllowed))
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
