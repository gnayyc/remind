import EventKit
import Foundation

// MARK: - Calendar Store Actor

actor CalendarStore {
    static let shared = CalendarStore()

    private let eventStore = EKEventStore()
    private let calendar = Calendar.current

    // MARK: - Authorization

    static func authorizationStatus() -> String {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .fullAccess: return "fullAccess"
        case .writeOnly: return "writeOnly"
        @unknown default: return "unknown"
        }
    }

    func requestAccess() async throws -> CalendarStore {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            return self
        case .notDetermined:
            let granted = try await eventStore.requestFullAccessToEvents()
            if !granted {
                throw CalendarError.accessDenied
            }
            return self
        default:
            throw CalendarError.accessDenied
        }
    }

    // MARK: - Calendar Management

    func defaultCalendarName() -> String? {
        eventStore.defaultCalendarForNewEvents?.title
    }

    func calendars() -> [CalendarInfo] {
        eventStore.calendars(for: .event).map { cal in
            CalendarInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                color: cal.cgColor.map { colorToHex($0) },
                isSubscribed: cal.isSubscribed,
                allowsModifications: cal.allowsContentModifications
            )
        }
    }

    func createCalendar(name: String) async throws -> CalendarInfo {
        let newCal = EKCalendar(for: .event, eventStore: eventStore)
        newCal.title = name

        guard let source = eventStore.defaultCalendarForNewEvents?.source else {
            throw CalendarError.noSource
        }
        newCal.source = source

        try eventStore.saveCalendar(newCal, commit: true)
        return CalendarInfo(
            id: newCal.calendarIdentifier,
            title: newCal.title,
            color: newCal.cgColor.map { colorToHex($0) },
            isSubscribed: false,
            allowsModifications: true
        )
    }

    func renameCalendar(oldName: String, newName: String) async throws {
        let cal = try findCalendar(named: oldName)
        guard cal.allowsContentModifications else {
            throw CalendarError.cannotModify
        }
        cal.title = newName
        try eventStore.saveCalendar(cal, commit: true)
    }

    func deleteCalendar(name: String) async throws {
        let cal = try findCalendar(named: name)
        guard cal.allowsContentModifications else {
            throw CalendarError.cannotModify
        }
        try eventStore.removeCalendar(cal, commit: true)
    }

    // MARK: - Event Creation

    func createEvent(
        title: String,
        calendarName: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String?,
        url: URL?,
        notes: String?,
        alarms: [String],
        recurrence: RecurrenceInfo?,
        attendees: [String]?
    ) async throws -> EventItem {
        let cal: EKCalendar
        if let name = calendarName {
            cal = try findCalendar(named: name)
        } else if let preferredCal = try? findCalendar(named: "cyyang") {
            cal = preferredCal
        } else if let defaultCal = eventStore.defaultCalendarForNewEvents {
            cal = defaultCal
        } else {
            throw CalendarError.noDefaultCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = cal
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.location = location
        event.url = url
        event.notes = notes

        // Alarms
        for alarmStr in alarms {
            if let alarm = parseAlarm(alarmStr, relativeTo: startDate) {
                event.addAlarm(alarm)
            }
        }

        // Recurrence
        if let rec = recurrence {
            let rule = makeRecurrenceRule(rec)
            event.recurrenceRules = [rule]
        }

        // Attendees (需要額外處理，EventKit 對 attendees 支援有限)
        // Note: 無法直接透過 EventKit 新增 attendees，需要透過 Calendar.app

        try eventStore.save(event, span: .thisEvent, commit: true)
        return eventItem(from: event)
    }

    // MARK: - Event Reading

    func events(filter: EventFilter) async throws -> [EventItem] {
        var calendars: [EKCalendar]?

        if let name = filter.calendarName {
            calendars = [try findCalendar(named: name)]
        } else if let ids = filter.calendarIDs {
            calendars = ids.compactMap { eventStore.calendar(withIdentifier: $0) }
        }

        let start = filter.startDate ?? Date()
        let end = filter.endDate ?? calendar.date(byAdding: .month, value: 1, to: start)!

        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
        )

        var events = eventStore.events(matching: predicate)

        if let search = filter.searchText?.lowercased() {
            events = events.filter { event in
                event.title?.lowercased().contains(search) == true ||
                event.notes?.lowercased().contains(search) == true ||
                event.location?.lowercased().contains(search) == true
            }
        }

        return events.map { eventItem(from: $0) }
    }

    func event(withID id: String) throws -> EventItem {
        guard let event = eventStore.event(withIdentifier: id) else {
            throw CalendarError.eventNotFound(id)
        }
        return eventItem(from: event)
    }

    // MARK: - Event Update

    func updateEvent(id: String, update: EventUpdate, span: EKSpan = .thisEvent) async throws -> EventItem {
        guard let event = eventStore.event(withIdentifier: id) else {
            throw CalendarError.eventNotFound(id)
        }

        if let title = update.title {
            event.title = title
        }
        if let notes = update.notes {
            event.notes = notes
        }
        if let location = update.location {
            event.location = location
        }
        if let url = update.url {
            event.url = url
        }
        if let start = update.startDate {
            event.startDate = start
        }
        if let end = update.endDate {
            event.endDate = end
        }
        if let allDay = update.isAllDay {
            event.isAllDay = allDay
        }

        // Alarms
        if update.clearAlarms {
            event.alarms?.forEach { event.removeAlarm($0) }
        }
        for alarmStr in update.alarms {
            if let alarm = parseAlarm(alarmStr, relativeTo: event.startDate) {
                event.addAlarm(alarm)
            }
        }

        // Recurrence
        if let recUpdate = update.recurrence {
            switch recUpdate {
            case .set(let rule):
                event.recurrenceRules = [rule]
            case .clear:
                event.recurrenceRules = nil
            }
        }

        try eventStore.save(event, span: span, commit: true)
        return eventItem(from: event)
    }

    // MARK: - Event Deletion

    func deleteEvent(id: String, span: EKSpan = .thisEvent) async throws -> String {
        guard let event = eventStore.event(withIdentifier: id) else {
            throw CalendarError.eventNotFound(id)
        }
        let title = event.title ?? "<unknown>"
        try eventStore.remove(event, span: span, commit: true)
        return title
    }

    // MARK: - Event Copy

    func copyEvent(id: String, toCalendar calendarName: String, newStartDate: Date? = nil) async throws -> EventItem {
        guard let originalEvent = eventStore.event(withIdentifier: id) else {
            throw CalendarError.eventNotFound(id)
        }

        let targetCal = try findCalendar(named: calendarName)

        let newEvent = EKEvent(eventStore: eventStore)
        newEvent.calendar = targetCal
        newEvent.title = originalEvent.title
        newEvent.notes = originalEvent.notes
        newEvent.location = originalEvent.location
        newEvent.url = originalEvent.url
        newEvent.isAllDay = originalEvent.isAllDay

        if let newStart = newStartDate {
            let duration = originalEvent.endDate.timeIntervalSince(originalEvent.startDate)
            newEvent.startDate = newStart
            newEvent.endDate = newStart.addingTimeInterval(duration)
        } else {
            newEvent.startDate = originalEvent.startDate
            newEvent.endDate = originalEvent.endDate
        }

        // Copy alarms
        originalEvent.alarms?.forEach { alarm in
            if let offset = alarm.relativeOffset as TimeInterval? {
                newEvent.addAlarm(EKAlarm(relativeOffset: offset))
            } else if let date = alarm.absoluteDate {
                newEvent.addAlarm(EKAlarm(absoluteDate: date))
            }
        }

        // Copy recurrence (optional - might want to make this configurable)
        if let rules = originalEvent.recurrenceRules {
            newEvent.recurrenceRules = rules.map { rule in
                EKRecurrenceRule(
                    recurrenceWith: rule.frequency,
                    interval: rule.interval,
                    end: rule.recurrenceEnd
                )
            }
        }

        try eventStore.save(newEvent, span: .thisEvent, commit: true)
        return eventItem(from: newEvent)
    }

    // MARK: - Recurring Event Operations

    /// 跳過重複事件的特定實例
    func skipOccurrence(eventID: String, date: Date) async throws {
        guard let event = eventStore.event(withIdentifier: eventID) else {
            throw CalendarError.eventNotFound(eventID)
        }

        // 找到該日期的實例
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let predicate = eventStore.predicateForEvents(
            withStart: dayStart,
            end: dayEnd,
            calendars: [event.calendar!]
        )

        let occurrences = eventStore.events(matching: predicate).filter {
            $0.eventIdentifier == eventID || $0.calendarItemExternalIdentifier == event.calendarItemExternalIdentifier
        }

        guard let occurrence = occurrences.first else {
            throw CalendarError.occurrenceNotFound(date)
        }

        try eventStore.remove(occurrence, span: .thisEvent, commit: true)
    }

    /// 修改重複事件的單一實例
    func modifyOccurrence(
        eventID: String,
        date: Date,
        update: EventUpdate
    ) async throws -> EventItem {
        guard let event = eventStore.event(withIdentifier: eventID) else {
            throw CalendarError.eventNotFound(eventID)
        }

        // 找到該日期的實例
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let predicate = eventStore.predicateForEvents(
            withStart: dayStart,
            end: dayEnd,
            calendars: [event.calendar!]
        )

        let occurrences = eventStore.events(matching: predicate).filter {
            $0.eventIdentifier == eventID || $0.calendarItemExternalIdentifier == event.calendarItemExternalIdentifier
        }

        guard let occurrence = occurrences.first else {
            throw CalendarError.occurrenceNotFound(date)
        }

        // 修改這個實例
        if let title = update.title {
            occurrence.title = title
        }
        if let notes = update.notes {
            occurrence.notes = notes
        }
        if let location = update.location {
            occurrence.location = location
        }
        if let start = update.startDate {
            occurrence.startDate = start
        }
        if let end = update.endDate {
            occurrence.endDate = end
        }

        try eventStore.save(occurrence, span: .thisEvent, commit: true)
        return eventItem(from: occurrence)
    }

    /// 列出重複事件的未來實例
    func listOccurrences(
        eventID: String,
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        limit: Int = 20
    ) async throws -> [EventInstance] {
        guard let event = eventStore.event(withIdentifier: eventID) else {
            throw CalendarError.eventNotFound(eventID)
        }

        let start = startDate ?? Date()
        let end = endDate ?? calendar.date(byAdding: .year, value: 1, to: start)!

        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: [event.calendar!]
        )

        let allEvents = eventStore.events(matching: predicate)
        let occurrences = allEvents.filter {
            $0.calendarItemExternalIdentifier == event.calendarItemExternalIdentifier
        }

        return Array(occurrences.prefix(limit)).map { occ in
            EventInstance(
                eventID: occ.eventIdentifier,
                occurrenceDate: occ.startDate,
                title: occ.title ?? "",
                startDate: occ.startDate,
                endDate: occ.endDate,
                isModified: occ.isDetached,
                isCancelled: false
            )
        }
    }

    // MARK: - Private Helpers

    private func findCalendar(named name: String) throws -> EKCalendar {
        guard let cal = eventStore.calendars(for: .event).first(where: {
            $0.title.lowercased() == name.lowercased()
        }) else {
            throw CalendarError.calendarNotFound(name)
        }
        return cal
    }

    private func eventItem(from event: EKEvent) -> EventItem {
        let alarms = event.alarms?.map { alarm -> AlarmInfo in
            if let date = alarm.absoluteDate {
                let formatter = ISO8601DateFormatter()
                return AlarmInfo(type: .absolute, value: formatter.string(from: date))
            } else {
                return AlarmInfo(type: .relative, value: String(alarm.relativeOffset))
            }
        } ?? []

        let attendees = event.attendees?.map { attendee in
            AttendeeInfo(
                name: attendee.name,
                email: attendee.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
                status: attendeeStatus(attendee.participantStatus),
                isOrganizer: attendee.isCurrentUser && event.organizer == attendee
            )
        } ?? []

        let recurrenceDesc = event.recurrenceRules?.first.map { rule -> String in
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

        return EventItem(
            id: event.eventIdentifier,
            title: event.title ?? "",
            notes: event.notes,
            location: event.location,
            url: event.url?.absoluteString,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            alarms: alarms,
            recurrence: recurrenceDesc,
            attendees: attendees,
            calendarID: event.calendar.calendarIdentifier,
            calendarName: event.calendar.title,
            isDetached: event.isDetached
        )
    }

    private func makeRecurrenceRule(_ info: RecurrenceInfo) -> EKRecurrenceRule {
        let end: EKRecurrenceEnd?
        switch info.end {
        case .date(let date):
            end = EKRecurrenceEnd(end: date)
        case .count(let count):
            end = EKRecurrenceEnd(occurrenceCount: count)
        case .none:
            end = nil
        }

        return EKRecurrenceRule(
            recurrenceWith: info.frequency,
            interval: info.interval,
            end: end
        )
    }

    private func attendeeStatus(_ status: EKParticipantStatus) -> String {
        switch status {
        case .accepted: return "accepted"
        case .declined: return "declined"
        case .tentative: return "tentative"
        case .pending: return "pending"
        case .unknown: return "unknown"
        case .delegated: return "delegated"
        case .completed: return "completed"
        case .inProcess: return "inProcess"
        @unknown default: return "unknown"
        }
    }

    private func colorToHex(_ cgColor: CGColor) -> String {
        guard let components = cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Calendar Errors

enum CalendarError: LocalizedError {
    case accessDenied
    case calendarNotFound(String)
    case eventNotFound(String)
    case occurrenceNotFound(Date)
    case noSource
    case noDefaultCalendar
    case cannotModify

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access denied. Grant permission in System Settings → Privacy & Security → Calendars"
        case .calendarNotFound(let name):
            return "Calendar not found: \(name)"
        case .eventNotFound(let id):
            return "Event not found: \(id)"
        case .occurrenceNotFound(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "No occurrence found on \(formatter.string(from: date))"
        case .noSource:
            return "No calendar source found"
        case .noDefaultCalendar:
            return "No default calendar. Create a calendar in Calendar.app first."
        case .cannotModify:
            return "Cannot modify this calendar"
        }
    }
}
