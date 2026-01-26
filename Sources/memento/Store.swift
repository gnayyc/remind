import CoreLocation
import EventKit
import Foundation

// MARK: - Models

struct ReminderItem: Codable {
    let id: String
    let title: String
    let notes: String?
    let isCompleted: Bool
    let completionDate: Date?
    let priority: String
    let flagged: Bool
    let url: String?
    let startDate: Date?
    let dueDate: Date?
    let alarms: [Date]
    let recurrence: String?
    let location: LocationInfo?
    let tags: [String]
    let subtasks: [ReminderItem]
    let listID: String
    let listName: String
    
    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(self)
        return String(data: data, encoding: .utf8)!
    }
    
    func formattedDates() -> String {
        var parts: [String] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        if let start = startDate {
            parts.append("from \(formatter.string(from: start))")
        }
        if let due = dueDate {
            parts.append("due \(formatter.string(from: due))")
        }
        if !alarms.isEmpty {
            parts.append("🔔 \(alarms.count)")
        }
        return parts.isEmpty ? "" : parts.joined(separator: ", ")
    }
}

struct ReminderList: Codable {
    let id: String
    let title: String
}

struct LocationInfo: Codable {
    let name: String?
    let latitude: Double
    let longitude: Double
    let radius: Double
    let proximity: String  // "arrive" or "leave"
}

struct ReminderFilter {
    var listName: String?
    var includeCompleted: Bool = false
    var onlyCompleted: Bool = false
    var dueDate: Date?
    var includeOverdue: Bool = false
}

enum DateFieldUpdate {
    case set(Date)
    case clear
}

enum RecurrenceUpdate {
    case set(EKRecurrenceRule)
    case clear
}

struct ReminderUpdate {
    var title: String?
    var notes: String?
    var priority: EKReminderPriority?
    var url: URL?
    var flagged: Bool?
    var tags: [String]?
    var startDate: DateFieldUpdate?
    var dueDate: DateFieldUpdate?
    var remindDate: DateFieldUpdate?
    var clearAlarms: Bool = false
    var additionalAlarms: [Date] = []
    var recurrence: RecurrenceUpdate?
    var clearLocation: Bool = false
    var location: LocationInfo?
}

// MARK: - Store Actor

actor RemindersStore {
    static let shared = RemindersStore()
    
    private let eventStore = EKEventStore()
    private let calendar = Calendar.current
    
    static func authorizationStatus() -> String {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .fullAccess: return "fullAccess"
        case .writeOnly: return "writeOnly"
        @unknown default: return "unknown"
        }
    }
    
    func requestAccess() async throws -> RemindersStore {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess:
            return self
        case .notDetermined:
            let granted = try await eventStore.requestFullAccessToReminders()
            if !granted {
                throw RemindError.accessDenied
            }
            return self
        default:
            throw RemindError.accessDenied
        }
    }
    
    func defaultListName() -> String? {
        eventStore.defaultCalendarForNewReminders()?.title
    }
    
    func lists() -> [ReminderList] {
        eventStore.calendars(for: .reminder).map {
            ReminderList(id: $0.calendarIdentifier, title: $0.title)
        }
    }
    
    func reminderCount(in listName: String) async throws -> Int {
        let cal = try calendar(named: listName)
        let predicate = eventStore.predicateForReminders(in: [cal])
        return await withCheckedContinuation { cont in
            eventStore.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders?.filter { !$0.isCompleted }.count ?? 0)
            }
        }
    }
    
    // MARK: - Create
    
    func createReminder(
        title: String,
        listName: String,
        notes: String?,
        priority: EKReminderPriority,
        url: URL?,
        flagged: Bool,
        tags: [String]?,
        startDate: Date?,
        dueDate: Date?,
        remindDate: Date?,
        additionalAlarms: [Date],
        recurrence: EKRecurrenceRule?,
        recurrenceEnd: Date?,
        location: LocationInfo?,
        parentID: String?
    ) async throws -> ReminderItem {
        let cal = try calendar(named: listName)
        let reminder = EKReminder(eventStore: eventStore)
        
        reminder.calendar = cal
        reminder.title = title
        reminder.notes = notes
        reminder.priority = Int(priority.rawValue)
        
        if let url = url {
            reminder.url = url
        }
        
        // Note: isFlagged is iOS only, using priority workaround for flagged
        // reminder.isFlagged = flagged  // Not available on macOS
        
        // Dates
        if let startDate = startDate {
            reminder.startDateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: startDate
            )
        }
        
        if let dueDate = dueDate {
            reminder.dueDateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        
        // Alarms
        var allAlarmDates = additionalAlarms
        if let remindDate = remindDate {
            allAlarmDates.insert(remindDate, at: 0)
        }
        for alarmDate in allAlarmDates {
            reminder.addAlarm(EKAlarm(absoluteDate: alarmDate))
        }
        
        // Recurrence
        if var rule = recurrence {
            if let endDate = recurrenceEnd {
                rule = EKRecurrenceRule(
                    recurrenceWith: rule.frequency,
                    interval: rule.interval,
                    end: EKRecurrenceEnd(end: endDate)
                )
            }
            reminder.recurrenceRules = [rule]
        }
        
        // Location-based alarm
        if let loc = location {
            let structuredLoc = EKStructuredLocation(title: loc.name ?? "Location")
            structuredLoc.geoLocation = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
            structuredLoc.radius = loc.radius
            
            let alarm = EKAlarm()
            alarm.structuredLocation = structuredLoc
            alarm.proximity = loc.proximity == "leave" ? .leave : .enter
            reminder.addAlarm(alarm)
        }
        
        try eventStore.save(reminder, commit: true)
        return reminderItem(from: reminder)
    }
    
    // MARK: - Read
    
    func reminders(filter: ReminderFilter) async throws -> [ReminderItem] {
        let calendars: [EKCalendar]
        if let listName = filter.listName {
            calendars = [try calendar(named: listName)]
        } else {
            calendars = eventStore.calendars(for: .reminder)
        }
        
        return await fetchAndFilter(calendars: calendars, filter: filter)
    }
    
    func allReminders(includeCompleted: Bool, dateFilter: DateFilter?) async throws -> [ReminderItem] {
        let calendars = eventStore.calendars(for: .reminder)
        var filter = ReminderFilter(includeCompleted: includeCompleted)
        
        if let df = dateFilter {
            filter.dueDate = df.targetDate
            filter.includeOverdue = df.includeOverdue
        }
        
        return await fetchAndFilter(calendars: calendars, filter: filter)
    }
    
    private func fetchAndFilter(calendars: [EKCalendar], filter: ReminderFilter) async -> [ReminderItem] {
        let predicate = eventStore.predicateForReminders(in: calendars)
        
        return await withCheckedContinuation { cont in
            eventStore.fetchReminders(matching: predicate) { [self] reminders in
                let filtered = (reminders ?? []).filter { reminder in
                    // Completion filter
                    if filter.onlyCompleted && !reminder.isCompleted {
                        return false
                    }
                    if !filter.includeCompleted && !filter.onlyCompleted && reminder.isCompleted {
                        return false
                    }
                    
                    // Due date filter
                    if let targetDate = filter.dueDate {
                        guard let reminderDue = reminder.dueDateComponents?.date else {
                            return false
                        }
                        let sameDay = calendar.isDate(reminderDue, inSameDayAs: targetDate)
                        let earlier = reminderDue < targetDate
                        
                        if !sameDay && !(filter.includeOverdue && earlier) {
                            return false
                        }
                    }
                    
                    return true
                }
                
                cont.resume(returning: filtered.map { self.reminderItem(from: $0) })
            }
        }
    }
    
    // MARK: - Update
    
    func updateReminder(id: String, listName: String?, update: ReminderUpdate) async throws -> ReminderItem {
        let reminder = try await findReminder(id: id, listName: listName)
        
        if let title = update.title {
            reminder.title = title
        }
        if let notes = update.notes {
            reminder.notes = notes
        }
        if let priority = update.priority {
            reminder.priority = Int(priority.rawValue)
        }
        if let url = update.url {
            reminder.url = url
        }
        // Note: isFlagged is iOS only
        // if let flagged = update.flagged {
        //     reminder.isFlagged = flagged
        // }
        
        // Start date
        if let startUpdate = update.startDate {
            switch startUpdate {
            case .set(let date):
                reminder.startDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            case .clear:
                reminder.startDateComponents = nil
            }
        }
        
        // Due date
        if let dueUpdate = update.dueDate {
            switch dueUpdate {
            case .set(let date):
                reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            case .clear:
                reminder.dueDateComponents = nil
            }
        }
        
        // Alarms
        if update.clearAlarms {
            reminder.alarms?.forEach { reminder.removeAlarm($0) }
        }
        if let remindUpdate = update.remindDate {
            if case .set(let date) = remindUpdate {
                reminder.addAlarm(EKAlarm(absoluteDate: date))
            }
        }
        for alarmDate in update.additionalAlarms {
            reminder.addAlarm(EKAlarm(absoluteDate: alarmDate))
        }
        
        // Recurrence
        if let recUpdate = update.recurrence {
            switch recUpdate {
            case .set(let rule):
                reminder.recurrenceRules = [rule]
            case .clear:
                reminder.recurrenceRules = nil
            }
        }
        
        // Location
        if update.clearLocation {
            reminder.alarms?.filter { $0.structuredLocation != nil }.forEach {
                reminder.removeAlarm($0)
            }
        }
        if let loc = update.location {
            let structuredLoc = EKStructuredLocation(title: loc.name ?? "Location")
            structuredLoc.geoLocation = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
            structuredLoc.radius = loc.radius
            
            let alarm = EKAlarm()
            alarm.structuredLocation = structuredLoc
            alarm.proximity = loc.proximity == "leave" ? .leave : .enter
            reminder.addAlarm(alarm)
        }
        
        try eventStore.save(reminder, commit: true)
        return reminderItem(from: reminder)
    }
    
    func setComplete(_ complete: Bool, id: String, listName: String?) async throws -> ReminderItem {
        let reminder = try await findReminder(id: id, listName: listName)
        reminder.isCompleted = complete
        if complete {
            reminder.completionDate = Date()
        } else {
            reminder.completionDate = nil
        }
        try eventStore.save(reminder, commit: true)
        return reminderItem(from: reminder)
    }
    
    // MARK: - Delete
    
    func deleteReminder(id: String, listName: String?) async throws -> String {
        let reminder = try await findReminder(id: id, listName: listName)
        let title = reminder.title ?? "<unknown>"
        try eventStore.remove(reminder, commit: true)
        return title
    }
    
    // MARK: - List Management
    
    func createList(name: String) async throws -> ReminderList {
        let newList = EKCalendar(for: .reminder, eventStore: eventStore)
        newList.title = name
        
        guard let source = eventStore.defaultCalendarForNewReminders()?.source else {
            throw RemindError.noSource
        }
        newList.source = source
        
        try eventStore.saveCalendar(newList, commit: true)
        return ReminderList(id: newList.calendarIdentifier, title: newList.title)
    }
    
    func renameList(oldName: String, newName: String) async throws {
        let cal = try calendar(named: oldName)
        guard cal.allowsContentModifications else {
            throw RemindError.cannotModify
        }
        cal.title = newName
        try eventStore.saveCalendar(cal, commit: true)
    }
    
    func deleteList(name: String) async throws {
        let cal = try calendar(named: name)
        guard cal.allowsContentModifications else {
            throw RemindError.cannotModify
        }
        try eventStore.removeCalendar(cal, commit: true)
    }
    
    // MARK: - Helpers
    
    private func calendar(named name: String) throws -> EKCalendar {
        guard let cal = eventStore.calendars(for: .reminder).first(where: {
            $0.title.lowercased() == name.lowercased()
        }) else {
            throw RemindError.listNotFound(name)
        }
        return cal
    }
    
    private func findReminder(id: String, listName: String?) async throws -> EKReminder {
        // Try as direct ID first
        if let item = eventStore.calendarItem(withIdentifier: id) as? EKReminder {
            return item
        }
        
        // Try as index
        if let index = Int(id) {
            let calendars: [EKCalendar]
            if let listName = listName {
                calendars = [try calendar(named: listName)]
            } else {
                calendars = eventStore.calendars(for: .reminder)
            }
            
            let predicate = eventStore.predicateForReminders(in: calendars)
            let reminders = await withCheckedContinuation { cont in
                eventStore.fetchReminders(matching: predicate) { reminders in
                    cont.resume(returning: reminders?.filter { !$0.isCompleted } ?? [])
                }
            }
            
            guard index >= 0 && index < reminders.count else {
                throw RemindError.notFound(id)
            }
            return reminders[index]
        }
        
        throw RemindError.notFound(id)
    }
    
    private func reminderItem(from reminder: EKReminder) -> ReminderItem {
        let alarms = reminder.alarms?.compactMap { alarm -> Date? in
            if alarm.structuredLocation != nil { return nil }
            return alarm.absoluteDate
        } ?? []
        
        let locationAlarm = reminder.alarms?.first { $0.structuredLocation != nil }
        let location: LocationInfo? = locationAlarm.flatMap { alarm in
            guard let loc = alarm.structuredLocation,
                  let geo = loc.geoLocation else { return nil }
            return LocationInfo(
                name: loc.title,
                latitude: geo.coordinate.latitude,
                longitude: geo.coordinate.longitude,
                radius: loc.radius,
                proximity: alarm.proximity == .leave ? "leave" : "arrive"
            )
        }
        
        let recurrenceDesc = reminder.recurrenceRules?.first.map { rule -> String in
            let freq: String
            switch rule.frequency {
            case .daily: freq = "daily"
            case .weekly: freq = "weekly"
            case .monthly: freq = "monthly"
            case .yearly: freq = "yearly"
            @unknown default: freq = "unknown"
            }
            return rule.interval > 1 ? "every \(rule.interval) \(freq)" : freq
        }
        
        // Get subtasks (macOS 14+)
        var subtasks: [ReminderItem] = []
        if #available(macOS 14, *) {
            // Note: subReminders API may need additional handling
        }
        
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            priority: priorityString(reminder.priority),
            flagged: false,  // isFlagged is iOS only
            url: reminder.url?.absoluteString,
            startDate: reminder.startDateComponents?.date,
            dueDate: reminder.dueDateComponents?.date,
            alarms: alarms,
            recurrence: recurrenceDesc,
            location: location,
            tags: [],  // Tags API varies by OS version
            subtasks: subtasks,
            listID: reminder.calendar.calendarIdentifier,
            listName: reminder.calendar.title
        )
    }
    
    private func priorityString(_ value: Int) -> String {
        switch value {
        case 1...4: return "high"
        case 5: return "medium"
        case 6...9: return "low"
        default: return "none"
        }
    }
}

// MARK: - Errors

enum RemindError: LocalizedError {
    case accessDenied
    case listNotFound(String)
    case notFound(String)
    case noSource
    case cannotModify
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access denied. Grant permission in System Settings → Privacy & Security → Reminders"
        case .listNotFound(let name):
            return "List not found: \(name)"
        case .notFound(let id):
            return "Reminder not found: \(id)"
        case .noSource:
            return "No reminder source found. Create a list in Reminders.app first."
        case .cannotModify:
            return "Cannot modify this list"
        }
    }
}
