import Foundation

enum VodDisplayFormatter {
    private static let ymdPattern = try! NSRegularExpression(
        pattern: #"(?<!\d)(20\d{2})(\d{2})(\d{2})(?!\d)"#
    )
    private static let breakTagPattern = try! NSRegularExpression(
        pattern: #"(?i)<br\s*/?>|</(?:p|div|li|h[1-6]|tr)>"#
    )
    private static let htmlTagPattern = try! NSRegularExpression(
        pattern: #"<[^>]+>"#
    )
    private static let whitespacePattern = try! NSRegularExpression(
        pattern: #"\s+"#
    )

    /// 去掉 MacCMS 简介里的 HTML 标签，只保留可读纯文本。
    static func plainText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var text = raw
        text = replace(breakTagPattern, in: text, with: " ")
        text = replace(htmlTagPattern, in: text, with: "")
        text = decodeHTMLEntities(text)
        text = replace(whitespacePattern, in: text, with: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// 将 MacCMS 原始备注（如「更新至 20260826期」）格式化为可读文案。
    static func formatRemarks(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return replaceEmbeddedDates(trimmed)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with replacement: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private static func replaceEmbeddedDates(_ text: String) -> String {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = ymdPattern.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges == 4,
                  let monthRange = Range(match.range(at: 2), in: result),
                  let dayRange = Range(match.range(at: 3), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }

            let month = String(result[monthRange])
            let day = String(result[dayRange])
            guard let monthValue = Int(month), let dayValue = Int(day),
                  (1...12).contains(monthValue), (1...31).contains(dayValue) else { continue }

            result.replaceSubrange(fullRange, with: "\(month)-\(day)")
        }
        return result
    }
}
