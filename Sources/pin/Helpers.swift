import EventKit
import Foundation

// MARK: - Date Parsing

func parseDate(_ string: String) -> Date? {
    let lowercased = string.lowercased()
    let calendar = Calendar.current
    let now = Date()
    
    // Relative dates
    switch lowercased {
    case "now":
        return now
    case "today":
        return calendar.startOfDay(for: now)
    case "tomorrow":
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    case "yesterday":
        return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
    default:
        break
    }
    
    // "in X minutes/hours/days/weeks"
    if lowercased.hasPrefix("in ") {
        let parts = lowercased.dropFirst(3).split(separator: " ")
        if parts.count >= 2, let value = Int(parts[0]) {
            let unit = String(parts[1])
            var component: Calendar.Component?
            if unit.hasPrefix("min") { component = .minute }
            else if unit.hasPrefix("hour") { component = .hour }
            else if unit.hasPrefix("day") { component = .day }
            else if unit.hasPrefix("week") { component = .weekOfYear }
            else if unit.hasPrefix("month") { component = .month }
            
            if let comp = component {
                return calendar.date(byAdding: comp, value: value, to: now)
            }
        }
    }
    
    // "next monday", "next week", etc.
    if lowercased.hasPrefix("next ") {
        let what = String(lowercased.dropFirst(5))
        switch what {
        case "week":
            return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        case "month":
            return calendar.date(byAdding: .month, value: 1, to: now)
        case "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday":
            let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
                          "thursday": 5, "friday": 6, "saturday": 7]
            if let targetWeekday = weekdays[what] {
                var components = DateComponents()
                components.weekday = targetWeekday
                return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
            }
        default:
            break
        }
    }
    
    // Time only: "9am", "14:30", "9:00am"
    let timePatterns: [(pattern: String, hasAmPm: Bool)] = [
        (#"^(\d{1,2}):(\d{2})\s*(am|pm)?$"#, true),
        (#"^(\d{1,2})(am|pm)$"#, true),
    ]
    
    for (pattern, _) in timePatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) {
            var hour = 0
            var minute = 0
            
            if let hourRange = Range(match.range(at: 1), in: string) {
                hour = Int(string[hourRange]) ?? 0
            }
            if match.numberOfRanges > 2, let minRange = Range(match.range(at: 2), in: string) {
                let minStr = string[minRange]
                if minStr.count == 2 && Int(minStr) != nil {
                    minute = Int(minStr) ?? 0
                }
            }
            
            // Check for am/pm
            let ampmRange = match.numberOfRanges > 2 ? match.range(at: match.numberOfRanges - 1) : NSRange(location: NSNotFound, length: 0)
            if ampmRange.location != NSNotFound, let range = Range(ampmRange, in: string) {
                let ampm = string[range].lowercased()
                if ampm == "pm" && hour < 12 { hour += 12 }
                if ampm == "am" && hour == 12 { hour = 0 }
            }
            
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            return calendar.date(from: components)
        }
    }
    
    // Standard date formats
    let formatters: [DateFormatter] = [
        {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return f
        }(),
        {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f
        }(),
        {
            let f = DateFormatter()
            f.dateFormat = "MM/dd/yyyy HH:mm"
            return f
        }(),
        {
            let f = DateFormatter()
            f.dateFormat = "MM/dd/yyyy"
            return f
        }(),
        {
            let f = DateFormatter()
            f.dateFormat = "MM/dd HH:mm"
            f.defaultDate = now
            return f
        }(),
        {
            let f = DateFormatter()
            f.dateFormat = "MM/dd"
            f.defaultDate = now
            return f
        }(),
    ]
    
    // ISO 8601
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFormatter.date(from: string) {
        return date
    }
    isoFormatter.formatOptions = [.withInternetDateTime]
    if let date = isoFormatter.date(from: string) {
        return date
    }
    
    for formatter in formatters {
        if let date = formatter.date(from: string) {
            return date
        }
    }
    
    return nil
}

// MARK: - Priority Parsing

func parsePriority(_ string: String?) -> EKReminderPriority {
    guard let string = string?.lowercased() else { return .none }
    switch string {
    case "high", "1": return .high
    case "medium", "med", "5": return .medium
    case "low", "9": return .low
    default: return .none
    }
}

// MARK: - Recurrence Parsing

func parseRecurrence(_ string: String, interval: Int?) -> EKRecurrenceRule? {
    let freq: EKRecurrenceFrequency
    switch string.lowercased() {
    case "daily", "day": freq = .daily
    case "weekly", "week": freq = .weekly
    case "monthly", "month": freq = .monthly
    case "yearly", "year": freq = .yearly
    default: return nil
    }
    
    return EKRecurrenceRule(
        recurrenceWith: freq,
        interval: interval ?? 1,
        end: nil
    )
}

// MARK: - Location Parsing

func parseLocation(_ options: LocationOptions) -> LocationInfo? {
    guard let lat = options.lat, let lon = options.lon else { return nil }
    return LocationInfo(
        name: options.location,
        latitude: lat,
        longitude: lon,
        radius: options.radius ?? 100,
        proximity: options.trigger ?? "arrive"
    )
}

// MARK: - Date Filter

struct DateFilter {
    let targetDate: Date
    let includeOverdue: Bool
}

func parseDateFilter(_ filter: String?) -> DateFilter? {
    guard let filter = filter?.lowercased() else { return nil }
    let calendar = Calendar.current
    let now = Date()
    
    switch filter {
    case "today":
        return DateFilter(targetDate: calendar.startOfDay(for: now), includeOverdue: false)
    case "tomorrow":
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return DateFilter(targetDate: tomorrow, includeOverdue: false)
    case "week":
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: now)!
        return DateFilter(targetDate: weekEnd, includeOverdue: true)
    case "overdue":
        return DateFilter(targetDate: calendar.startOfDay(for: now), includeOverdue: true)
    default:
        return nil
    }
}

// MARK: - Output Helpers

func printReminders(_ reminders: [ReminderItem], json: Bool, plain: Bool) {
    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(reminders)
        print(String(data: data, encoding: .utf8)!)
        return
    }
    
    if plain {
        for (i, r) in reminders.enumerated() {
            let dates = [r.startDate, r.dueDate].compactMap { $0?.ISO8601Format() }.joined(separator: "\t")
            print("\(i)\t\(r.id)\t\(r.title)\t\(dates)\t\(r.listName)")
        }
        return
    }
    
    // Pretty output
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    
    for (i, r) in reminders.enumerated() {
        var line = "\(i): "
        
        if r.isCompleted {
            line += "✓ "
        }
        if r.flagged {
            line += "🚩 "
        }
        if r.priority == "high" {
            line += "❗ "
        }
        
        line += r.title
        
        var meta: [String] = []
        if let due = r.dueDate {
            let relative = relativeDate(due)
            meta.append("due \(relative)")
        }
        if let start = r.startDate {
            meta.append("from \(formatter.string(from: start))")
        }
        if !r.alarms.isEmpty {
            meta.append("🔔\(r.alarms.count)")
        }
        if let rec = r.recurrence {
            meta.append("🔄 \(rec)")
        }
        if r.location != nil {
            meta.append("📍")
        }
        
        if !meta.isEmpty {
            line += " (\(meta.joined(separator: ", ")))"
        }
        
        print(line)
    }
    
    if reminders.isEmpty {
        print("No reminders found.")
    }
}

func relativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}
