import EventKit
import Foundation

// MARK: - Alarm Time Parsing

/// 解析相對時間格式，回傳相對於事件開始時間的 TimeInterval（負值表示之前）
/// 支援格式：
/// - "10m", "30min" - 分鐘
/// - "1h", "2hr", "2hour" - 小時
/// - "1d", "2day" - 天
/// - "1w", "2wk", "2week" - 週
/// - "1d 9:00" - 天數 + 特定時間
/// - 絕對時間會回傳 nil（需另外處理）
func parseRelativeAlarm(_ string: String) -> TimeInterval? {
    let lowercased = string.lowercased().trimmingCharacters(in: .whitespaces)

    // 檢查是否有特定時間（如 "1d 9:00"）
    let parts = lowercased.split(separator: " ", maxSplits: 1)

    guard let firstPart = parts.first else { return nil }
    let durationPart = String(firstPart)

    // 解析數值和單位
    let pattern = #"^(\d+)\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|wk|wks|week|weeks)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: durationPart, range: NSRange(durationPart.startIndex..., in: durationPart)),
          let valueRange = Range(match.range(at: 1), in: durationPart),
          let unitRange = Range(match.range(at: 2), in: durationPart),
          let value = Int(durationPart[valueRange]) else {
        return nil
    }

    let unit = String(durationPart[unitRange]).lowercased()

    var seconds: TimeInterval
    switch unit {
    case "m", "min", "mins", "minute", "minutes":
        seconds = TimeInterval(value * 60)
    case "h", "hr", "hrs", "hour", "hours":
        seconds = TimeInterval(value * 3600)
    case "d", "day", "days":
        seconds = TimeInterval(value * 86400)
    case "w", "wk", "wks", "week", "weeks":
        seconds = TimeInterval(value * 604800)
    default:
        return nil
    }

    return -seconds  // 負值表示事件之前
}

/// 解析 alarm 字串，回傳 EKAlarm
/// 支援：
/// - 相對時間："10m", "1h", "1d", "1w"
/// - 帶特定時間："1d 9:00"（1 天前的早上 9 點）
/// - 絕對時間："2024-01-29 18:00"
func parseAlarm(_ string: String, relativeTo eventDate: Date? = nil) -> EKAlarm? {
    let trimmed = string.trimmingCharacters(in: .whitespaces)

    // 嘗試解析為相對時間
    if let offset = parseRelativeAlarm(trimmed) {
        return EKAlarm(relativeOffset: offset)
    }

    // 嘗試解析為 "1d 9:00" 格式
    if let alarm = parseRelativeAlarmWithTime(trimmed, relativeTo: eventDate) {
        return alarm
    }

    // 嘗試解析為絕對時間
    if let date = parseDate(trimmed) {
        return EKAlarm(absoluteDate: date)
    }

    return nil
}

/// 解析 "1d 9:00" 格式（N天前的特定時間）
private func parseRelativeAlarmWithTime(_ string: String, relativeTo eventDate: Date?) -> EKAlarm? {
    let parts = string.lowercased().split(separator: " ", maxSplits: 1)
    guard parts.count == 2 else { return nil }

    let durationPart = String(parts[0])
    let timePart = String(parts[1])

    // 解析天數/週數
    let pattern = #"^(\d+)\s*(d|day|days|w|wk|wks|week|weeks)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: durationPart, range: NSRange(durationPart.startIndex..., in: durationPart)),
          let valueRange = Range(match.range(at: 1), in: durationPart),
          let unitRange = Range(match.range(at: 2), in: durationPart),
          let value = Int(durationPart[valueRange]) else {
        return nil
    }

    let unit = String(durationPart[unitRange]).lowercased()
    let days: Int
    switch unit {
    case "d", "day", "days":
        days = value
    case "w", "wk", "wks", "week", "weeks":
        days = value * 7
    default:
        return nil
    }

    // 解析時間
    guard let time = parseTimeOnly(timePart) else { return nil }

    // 如果有事件日期，計算絕對時間
    if let eventDate = eventDate {
        let calendar = Calendar.current
        var targetDate = calendar.date(byAdding: .day, value: -days, to: eventDate)!
        var components = calendar.dateComponents([.year, .month, .day], from: targetDate)
        components.hour = time.hour
        components.minute = time.minute
        if let alarmDate = calendar.date(from: components) {
            return EKAlarm(absoluteDate: alarmDate)
        }
    }

    // 沒有事件日期時，使用相對 offset（不精確，但可用）
    let offset = TimeInterval(-days * 86400)
    return EKAlarm(relativeOffset: offset)
}

/// 解析時間字串，回傳小時和分鐘
private func parseTimeOnly(_ string: String) -> (hour: Int, minute: Int)? {
    let patterns: [(pattern: String, hourGroup: Int, minuteGroup: Int?, ampmGroup: Int?)] = [
        (#"^(\d{1,2}):(\d{2})(?:\s*(am|pm))?$"#, 1, 2, 3),
        (#"^(\d{1,2})(am|pm)$"#, 1, nil, 2),
    ]

    for (pattern, hourGroup, minuteGroup, ampmGroup) in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let hourRange = Range(match.range(at: hourGroup), in: string),
              var hour = Int(string[hourRange]) else {
            continue
        }

        var minute = 0
        if let minGroup = minuteGroup,
           let minRange = Range(match.range(at: minGroup), in: string) {
            minute = Int(string[minRange]) ?? 0
        }

        if let ampmIdx = ampmGroup,
           match.range(at: ampmIdx).location != NSNotFound,
           let ampmRange = Range(match.range(at: ampmIdx), in: string) {
            let ampm = string[ampmRange].lowercased()
            if ampm == "pm" && hour < 12 { hour += 12 }
            if ampm == "am" && hour == 12 { hour = 0 }
        }

        return (hour, minute)
    }

    return nil
}

/// 解析 duration 字串，回傳秒數
/// 支援："30m", "1h", "1.5h", "90min", "1h30m"
func parseDuration(_ string: String) -> TimeInterval? {
    let lowercased = string.lowercased().trimmingCharacters(in: .whitespaces)

    // 複合格式: "1h30m"
    let compoundPattern = #"^(\d+)h\s*(\d+)m$"#
    if let regex = try? NSRegularExpression(pattern: compoundPattern, options: .caseInsensitive),
       let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
       let hoursRange = Range(match.range(at: 1), in: lowercased),
       let minsRange = Range(match.range(at: 2), in: lowercased),
       let hours = Int(lowercased[hoursRange]),
       let mins = Int(lowercased[minsRange]) {
        return TimeInterval(hours * 3600 + mins * 60)
    }

    // 單一格式: "30m", "1h", "1.5h"
    let pattern = #"^(\d+(?:\.\d+)?)\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
          let valueRange = Range(match.range(at: 1), in: lowercased),
          let unitRange = Range(match.range(at: 2), in: lowercased),
          let value = Double(lowercased[valueRange]) else {
        return nil
    }

    let unit = String(lowercased[unitRange])
    switch unit {
    case "m", "min", "mins", "minute", "minutes":
        return value * 60
    case "h", "hr", "hrs", "hour", "hours":
        return value * 3600
    default:
        return nil
    }
}
