import Foundation

// MARK: - Template Models

enum TemplateType: String, Codable {
    case event
    case reminder
}

struct Template: Codable {
    let name: String
    let type: TemplateType
    let title: String
    let notes: String?

    // Event-specific
    let duration: String?
    let calendar: String?
    let location: String?
    let url: String?

    // Reminder-specific
    let list: String?
    let priority: String?
    let startDate: String?
    let dueDate: String?
    let flagged: Bool?
    let tags: [String]?
    let locationReminder: LocationReminderTemplate?

    // Shared
    let alarms: [String]?
    let recurrence: RecurrenceTemplate?

    init(
        name: String,
        type: TemplateType,
        title: String,
        notes: String? = nil,
        duration: String? = nil,
        calendar: String? = nil,
        location: String? = nil,
        url: String? = nil,
        list: String? = nil,
        priority: String? = nil,
        startDate: String? = nil,
        dueDate: String? = nil,
        flagged: Bool? = nil,
        tags: [String]? = nil,
        locationReminder: LocationReminderTemplate? = nil,
        alarms: [String]? = nil,
        recurrence: RecurrenceTemplate? = nil
    ) {
        self.name = name
        self.type = type
        self.title = title
        self.notes = notes
        self.duration = duration
        self.calendar = calendar
        self.location = location
        self.url = url
        self.list = list
        self.priority = priority
        self.startDate = startDate
        self.dueDate = dueDate
        self.flagged = flagged
        self.tags = tags
        self.locationReminder = locationReminder
        self.alarms = alarms
        self.recurrence = recurrence
    }
}

struct RecurrenceTemplate: Codable {
    let frequency: String  // daily, weekly, monthly, yearly
    let interval: Int?
    let end: String?  // date string or nil
    let count: Int?
}

struct LocationReminderTemplate: Codable {
    let name: String?
    let lat: Double
    let lon: Double
    let radius: Double?
    let trigger: String?  // arrive, leave
}

// MARK: - Template Variables

struct TemplateVariables {
    let date: Date
    let customVars: [String: String]

    init(date: Date = Date(), customVars: [String: String] = [:]) {
        self.date = date
        self.customVars = customVars
    }

    func expand(_ string: String) -> String {
        var result = string
        let calendar = Calendar.current

        // Built-in variables
        let dateFormatter = DateFormatter()

        // {date} -> 2024-01-30
        dateFormatter.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: date))

        // {week} -> W05
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        result = result.replacingOccurrences(of: "{week}", with: String(format: "W%02d", weekOfYear))

        // {month} -> January
        dateFormatter.dateFormat = "MMMM"
        result = result.replacingOccurrences(of: "{month}", with: dateFormatter.string(from: date))

        // {year} -> 2024
        let year = calendar.component(.year, from: date)
        result = result.replacingOccurrences(of: "{year}", with: String(year))

        // {weekday} -> Monday
        dateFormatter.dateFormat = "EEEE"
        result = result.replacingOccurrences(of: "{weekday}", with: dateFormatter.string(from: date))

        // Custom variables
        for (key, value) in customVars {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }

        return result
    }
}

// MARK: - Template Summary (for listing)

struct TemplateSummary: Codable {
    let name: String
    let type: TemplateType
    let title: String
    let hasRecurrence: Bool
    let alarmCount: Int
}

extension Template {
    func summary() -> TemplateSummary {
        TemplateSummary(
            name: name,
            type: type,
            title: title,
            hasRecurrence: recurrence != nil,
            alarmCount: alarms?.count ?? 0
        )
    }
}
