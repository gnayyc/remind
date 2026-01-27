import Foundation

// MARK: - Output Formatting

/// 輸出格式
enum OutputFormat {
    case pretty
    case json
    case plain
}

/// 相對日期格式化（使用 Helpers.swift 中的 relativeDate）

/// 時間範圍格式化
func formatTimeRange(start: Date, end: Date, allDay: Bool) -> String {
    if allDay {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: start)
    }

    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short

    return "\(formatter.string(from: start))-\(formatter.string(from: end))"
}

/// 日期標題格式化（用於 today/week 檢視）
func formatDateHeader(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_TW")
    formatter.dateFormat = "yyyy-MM-dd (EEEE)"
    return formatter.string(from: date)
}

/// JSON 編碼器（共用設定）
func makeJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

/// 將任何 Encodable 轉為 JSON 字串
func toJSON<T: Encodable>(_ value: T) -> String {
    let encoder = makeJSONEncoder()
    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

// MARK: - Color Output (ANSI)

enum ANSIColor: String {
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
    case dim = "\u{001B}[2m"
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
}

/// 檢查是否支援顏色輸出
var supportsColor: Bool {
    guard let term = ProcessInfo.processInfo.environment["TERM"] else {
        return false
    }
    return term != "dumb" && isatty(fileno(stdout)) != 0
}

/// 套用顏色
func colored(_ string: String, _ color: ANSIColor) -> String {
    guard supportsColor else { return string }
    return "\(color.rawValue)\(string)\(ANSIColor.reset.rawValue)"
}

// MARK: - Table Formatting

/// 簡易表格格式化
struct TableFormatter {
    var columns: [(title: String, width: Int)]
    var separator: String = "  "

    func header() -> String {
        columns.map { $0.title.padding(toLength: $0.width, withPad: " ", startingAt: 0) }
            .joined(separator: separator)
    }

    func row(_ values: [String]) -> String {
        zip(columns, values).map { col, val in
            val.padding(toLength: col.width, withPad: " ", startingAt: 0)
        }.joined(separator: separator)
    }

    func divider() -> String {
        columns.map { String(repeating: "-", count: $0.width) }
            .joined(separator: separator)
    }
}
