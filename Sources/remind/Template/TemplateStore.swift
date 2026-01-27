import Foundation
import Yams

// MARK: - Template Store

actor TemplateStore {
    static let shared = TemplateStore()

    private let templatesDir: URL

    init() {
        // ~/.config/remind/templates/
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        templatesDir = homeDir
            .appendingPathComponent(".config")
            .appendingPathComponent("remind")
            .appendingPathComponent("templates")
    }

    // MARK: - Directory Management

    func ensureDirectoryExists() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: templatesDir.path) {
            try fm.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - CRUD Operations

    func save(_ template: Template) async throws {
        try ensureDirectoryExists()

        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(template)

        let fileURL = templatesDir.appendingPathComponent("\(template.name).yaml")
        try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func load(name: String) async throws -> Template {
        let fileURL = templatesDir.appendingPathComponent("\(name).yaml")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TemplateError.notFound(name)
        }

        let yaml = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = YAMLDecoder()
        return try decoder.decode(Template.self, from: yaml)
    }

    func list() async throws -> [TemplateSummary] {
        try ensureDirectoryExists()

        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: templatesDir, includingPropertiesForKeys: nil)

        var templates: [TemplateSummary] = []

        for url in contents where url.pathExtension == "yaml" {
            do {
                let yaml = try String(contentsOf: url, encoding: .utf8)
                let decoder = YAMLDecoder()
                let template = try decoder.decode(Template.self, from: yaml)
                templates.append(template.summary())
            } catch {
                // Skip invalid templates
                continue
            }
        }

        return templates.sorted { $0.name < $1.name }
    }

    func delete(name: String) async throws {
        let fileURL = templatesDir.appendingPathComponent("\(name).yaml")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TemplateError.notFound(name)
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    func exists(name: String) -> Bool {
        let fileURL = templatesDir.appendingPathComponent("\(name).yaml")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Template Application

    /// 將範本套用到事件建立
    func applyToEvent(
        template: Template,
        startDate: Date,
        overrides: EventTemplateOverrides,
        variables: TemplateVariables
    ) -> AppliedEventTemplate {
        let title = variables.expand(overrides.title ?? template.title)
        let notes = (overrides.notes ?? template.notes).map { variables.expand($0) }

        // Calculate end date
        let endDate: Date
        if let durationStr = template.duration, let duration = parseDuration(durationStr) {
            endDate = startDate.addingTimeInterval(duration)
        } else {
            endDate = startDate.addingTimeInterval(3600)  // Default 1 hour
        }

        return AppliedEventTemplate(
            title: title,
            calendar: overrides.calendar ?? template.calendar,
            startDate: startDate,
            endDate: endDate,
            location: overrides.location ?? template.location,
            url: template.url,
            notes: notes,
            alarms: template.alarms ?? [],
            recurrence: template.recurrence
        )
    }

    /// 將範本套用到提醒建立
    func applyToReminder(
        template: Template,
        baseDate: Date?,
        overrides: ReminderTemplateOverrides,
        variables: TemplateVariables
    ) -> AppliedReminderTemplate {
        let title = variables.expand(overrides.title ?? template.title)
        let notes = (overrides.notes ?? template.notes).map { variables.expand($0) }

        // Parse dates relative to baseDate
        let now = baseDate ?? Date()
        let startDate = template.startDate.flatMap { parseRelativeOrAbsoluteDate($0, relativeTo: now) }
        let dueDate = template.dueDate.flatMap { parseRelativeOrAbsoluteDate($0, relativeTo: now) }

        return AppliedReminderTemplate(
            title: title,
            list: overrides.list ?? template.list,
            notes: notes,
            priority: template.priority,
            startDate: overrides.startDate ?? startDate,
            dueDate: overrides.dueDate ?? dueDate,
            alarms: template.alarms ?? [],
            recurrence: template.recurrence,
            location: template.locationReminder,
            flagged: template.flagged ?? false,
            tags: template.tags
        )
    }
}

// MARK: - Applied Templates

struct AppliedEventTemplate {
    let title: String
    let calendar: String?
    let startDate: Date
    let endDate: Date
    let location: String?
    let url: String?
    let notes: String?
    let alarms: [String]
    let recurrence: RecurrenceTemplate?
}

struct AppliedReminderTemplate {
    let title: String
    let list: String?
    let notes: String?
    let priority: String?
    let startDate: Date?
    let dueDate: Date?
    let alarms: [String]
    let recurrence: RecurrenceTemplate?
    let location: LocationReminderTemplate?
    let flagged: Bool
    let tags: [String]?
}

// MARK: - Template Overrides

struct EventTemplateOverrides {
    var title: String?
    var calendar: String?
    var location: String?
    var notes: String?
}

struct ReminderTemplateOverrides {
    var title: String?
    var list: String?
    var notes: String?
    var startDate: Date?
    var dueDate: Date?
}

// MARK: - Helper

/// 解析相對或絕對日期字串
/// 支援 "friday 17:00", "2024-01-30 09:00" 等格式
private func parseRelativeOrAbsoluteDate(_ string: String, relativeTo baseDate: Date) -> Date? {
    // 先嘗試解析絕對日期
    if let date = parseDate(string) {
        return date
    }

    // 嘗試解析為星期幾 + 時間格式 (e.g., "friday 17:00")
    let parts = string.lowercased().split(separator: " ", maxSplits: 1)
    if parts.count == 2 {
        let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
                        "thursday": 5, "friday": 6, "saturday": 7]

        if let targetWeekday = weekdays[String(parts[0])] {
            let calendar = Calendar.current
            var components = DateComponents()
            components.weekday = targetWeekday

            if let nextDay = calendar.nextDate(after: baseDate, matching: components, matchingPolicy: .nextTime) {
                // Parse time part
                let timeStr = String(parts[1])
                if let (hour, minute) = parseTimeComponents(timeStr) {
                    var dateComponents = calendar.dateComponents([.year, .month, .day], from: nextDay)
                    dateComponents.hour = hour
                    dateComponents.minute = minute
                    return calendar.date(from: dateComponents)
                }
            }
        }
    }

    return nil
}

private func parseTimeComponents(_ string: String) -> (hour: Int, minute: Int)? {
    let pattern = #"^(\d{1,2}):(\d{2})$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
          let hourRange = Range(match.range(at: 1), in: string),
          let minRange = Range(match.range(at: 2), in: string),
          let hour = Int(string[hourRange]),
          let minute = Int(string[minRange]) else {
        return nil
    }
    return (hour, minute)
}

// MARK: - Errors

enum TemplateError: LocalizedError {
    case notFound(String)
    case invalidFormat(String)
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "Template not found: \(name)"
        case .invalidFormat(let detail):
            return "Invalid template format: \(detail)"
        case .alreadyExists(let name):
            return "Template already exists: \(name)"
        }
    }
}
