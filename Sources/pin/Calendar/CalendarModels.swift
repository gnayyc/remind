import EventKit
import Foundation

// MARK: - Calendar Event Model

struct EventItem: Codable {
    let id: String
    let title: String
    let notes: String?
    let location: String?
    let url: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let alarms: [AlarmInfo]
    let recurrence: String?
    let attendees: [AttendeeInfo]
    let calendarID: String
    let calendarName: String
    let isDetached: Bool  // 是否為重複事件的修改實例

    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(self)
        return String(data: data, encoding: .utf8)!
    }

    func formattedTime() -> String {
        if isAllDay {
            return "all-day"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(formatter.string(from: startDate))-\(formatter.string(from: endDate))"
    }

    func formattedDateRange() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        if isAllDay {
            formatter.timeStyle = .none
            let calendar = Calendar.current
            if calendar.isDate(startDate, inSameDayAs: endDate) ||
               calendar.isDate(startDate, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: endDate)!) {
                return formatter.string(from: startDate)
            }
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }

        let calendar = Calendar.current
        if calendar.isDate(startDate, inSameDayAs: endDate) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short
            return "\(formatter.string(from: startDate)) - \(timeFormatter.string(from: endDate))"
        }

        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
}

struct AlarmInfo: Codable {
    let type: AlarmType
    let value: String  // "-600" (relative offset) or "2024-01-30T09:00:00" (absolute)

    enum AlarmType: String, Codable {
        case relative
        case absolute
    }

    var description: String {
        switch type {
        case .relative:
            guard let offset = Double(value) else { return value }
            let absOffset = abs(offset)
            if absOffset < 3600 {
                return "\(Int(absOffset / 60))m before"
            } else if absOffset < 86400 {
                return "\(Int(absOffset / 3600))h before"
            } else if absOffset < 604800 {
                return "\(Int(absOffset / 86400))d before"
            } else {
                return "\(Int(absOffset / 604800))w before"
            }
        case .absolute:
            return value
        }
    }
}

struct AttendeeInfo: Codable {
    let name: String?
    let email: String?
    let status: String  // "accepted", "declined", "tentative", "pending"
    let isOrganizer: Bool
}

// MARK: - Calendar List Model

struct CalendarInfo: Codable {
    let id: String
    let title: String
    let color: String?
    let isSubscribed: Bool
    let allowsModifications: Bool
}

// MARK: - Event Filter

struct EventFilter {
    var calendarName: String?
    var calendarIDs: [String]?
    var startDate: Date?
    var endDate: Date?
    var searchText: String?
}

// MARK: - Event Update

enum DateTimeUpdate {
    case set(Date)
    case clear
}

struct EventUpdate {
    var title: String? = nil
    var notes: String? = nil
    var location: String? = nil
    var url: URL? = nil
    var startDate: Date? = nil
    var endDate: Date? = nil
    var isAllDay: Bool? = nil
    var clearAlarms: Bool = false
    var alarms: [String] = []  // 新增的 alarm 字串
    var recurrence: RecurrenceUpdate? = nil
    var attendees: [String]? = nil  // email 列表

    init(
        title: String? = nil,
        notes: String? = nil,
        location: String? = nil,
        url: URL? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isAllDay: Bool? = nil,
        clearAlarms: Bool = false,
        alarms: [String] = [],
        recurrence: RecurrenceUpdate? = nil,
        attendees: [String]? = nil
    ) {
        self.title = title
        self.notes = notes
        self.location = location
        self.url = url
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.clearAlarms = clearAlarms
        self.alarms = alarms
        self.recurrence = recurrence
        self.attendees = attendees
    }
}

// Note: RecurrenceUpdate is defined in Store.swift

// MARK: - Recurrence Info

struct RecurrenceInfo {
    let frequency: EKRecurrenceFrequency
    let interval: Int
    let end: RecurrenceEnd?

    enum RecurrenceEnd {
        case date(Date)
        case count(Int)
    }
}

// MARK: - Event Instance (for recurring events)

struct EventInstance: Codable {
    let eventID: String
    let occurrenceDate: Date
    let title: String
    let startDate: Date
    let endDate: Date
    let isModified: Bool  // 是否被修改過
    let isCancelled: Bool  // 是否被跳過
}
