import Foundation

enum VodDisplayFormatter {
    private static let ymdPattern = try! NSRegularExpression(
        pattern: #"(?<!\d)(20\d{2})(\d{2})(\d{2})(?!\d)"#
    )

    /// 将 MacCMS 原始备注（如「更新至 20260826期」）格式化为可读文案。
    static func formatRemarks(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return replaceEmbeddedDates(trimmed)
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
