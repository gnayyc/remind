import ArgumentParser
import EventKit
import Foundation

// MARK: - Event Command Group

struct Event: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "event",
        abstract: "Manage calendar events",
        subcommands: [
            EventAdd.self,
            EventShow.self,
            EventAll.self,
            EventEdit.self,
            EventDelete.self,
            EventCopy.self,
            EventSkip.self,
            EventModify.self,
            EventInstances.self,
        ],
        defaultSubcommand: EventAll.self,
        aliases: ["e"]
    )
}

// MARK: - Event Add

struct EventAdd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a new calendar event"
    )

    @Argument(help: "Event title")
    var title: String

    @Option(name: [.short, .long], help: "Calendar name")
    var calendar: String?

    // Time options
    @Option(name: .long, help: "Start date/time")
    var start: String?

    @Option(name: .long, help: "End date/time")
    var end: String?

    @Option(name: [.short, .long], help: "Duration (e.g., 1h, 30m, 1h30m)")
    var duration: String?

    @Flag(name: .long, help: "All-day event")
    var allDay = false

    @Option(name: .long, help: "Date for all-day event")
    var date: String?

    // Details
    @Option(name: [.short, .long], help: "Location")
    var location: String?

    @Option(name: .long, help: "URL")
    var url: String?

    @Option(name: [.short, .long], help: "Notes")
    var notes: String?

    // Alarms
    @Option(name: .long, help: "Alarm (can specify multiple: 10m, 1h, 1d, 1d 9:00)")
    var alarm: [String] = []

    // Recurrence
    @Option(name: .long, help: "Recurrence: daily, weekly, monthly, yearly")
    var recurrence: String?

    @Option(name: .long, help: "Recurrence interval")
    var interval: Int?

    @Option(name: .long, help: "End repeat on date")
    var repeatEnd: String?

    @Option(name: .long, help: "Repeat count")
    var repeatCount: Int?

    // Attendees
    @Option(name: .long, help: "Attendee email (can specify multiple)")
    var attendee: [String] = []

    // Template
    @Option(name: [.short, .long], help: "Use template")
    var template: String?

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()

        // Parse dates
        let (startDate, endDate) = try parseDateRange()

        // Parse recurrence
        let recurrenceInfo = parseRecurrenceInfo()

        let event = try await store.createEvent(
            title: title,
            calendarName: calendar,
            startDate: startDate,
            endDate: endDate,
            isAllDay: allDay,
            location: location,
            url: url.flatMap { URL(string: $0) },
            notes: notes,
            alarms: alarm,
            recurrence: recurrenceInfo,
            attendees: attendee.isEmpty ? nil : attendee
        )

        if output.json {
            print(event.toJSON())
        } else {
            print("✓ \(event.title) [\(event.calendarName)] — \(event.formattedDateRange())")
        }
    }

    private func parseDateRange() throws -> (Date, Date) {
        if allDay {
            // All-day event
            guard let dateStr = date ?? start else {
                throw ValidationError("All-day event requires --date or --start")
            }
            guard let startDate = parseDate(dateStr) else {
                throw ValidationError("Invalid date: \(dateStr)")
            }
            let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
            return (startDate, endDate)
        }

        guard let startStr = start else {
            throw ValidationError("Event requires --start (or --all-day with --date)")
        }
        guard let startDate = parseDate(startStr) else {
            throw ValidationError("Invalid start date: \(startStr)")
        }

        let endDate: Date
        if let endStr = end {
            guard let parsed = parseDate(endStr) else {
                throw ValidationError("Invalid end date: \(endStr)")
            }
            endDate = parsed
        } else if let durationStr = duration {
            guard let seconds = parseDuration(durationStr) else {
                throw ValidationError("Invalid duration: \(durationStr)")
            }
            endDate = startDate.addingTimeInterval(seconds)
        } else {
            // Default: 1 hour
            endDate = startDate.addingTimeInterval(3600)
        }

        return (startDate, endDate)
    }

    private func parseRecurrenceInfo() -> RecurrenceInfo? {
        guard let recStr = recurrence else { return nil }

        let freq: EKRecurrenceFrequency
        switch recStr.lowercased() {
        case "daily", "day": freq = .daily
        case "weekly", "week": freq = .weekly
        case "monthly", "month": freq = .monthly
        case "yearly", "year": freq = .yearly
        default: return nil
        }

        let end: RecurrenceInfo.RecurrenceEnd?
        if let endDate = repeatEnd.flatMap({ parseDate($0) }) {
            end = .date(endDate)
        } else if let count = repeatCount {
            end = .count(count)
        } else {
            end = nil
        }

        return RecurrenceInfo(
            frequency: freq,
            interval: interval ?? 1,
            end: end
        )
    }
}

// MARK: - Event Show

struct EventShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show events in a calendar"
    )

    @Argument(help: "Calendar name")
    var calendarName: String

    @Option(name: .long, help: "Start date (default: today)")
    var from: String?

    @Option(name: .long, help: "End date (default: 1 month from start)")
    var to: String?

    @Option(name: .long, help: "Number of days to show")
    var days: Int?

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()

        let startDate = from.flatMap { parseDate($0) } ?? Calendar.current.startOfDay(for: Date())
        let endDate: Date
        if let toStr = to, let parsed = parseDate(toStr) {
            endDate = parsed
        } else if let d = days {
            endDate = Calendar.current.date(byAdding: .day, value: d, to: startDate)!
        } else {
            endDate = Calendar.current.date(byAdding: .month, value: 1, to: startDate)!
        }

        let filter = EventFilter(
            calendarName: calendarName,
            startDate: startDate,
            endDate: endDate
        )

        let events = try await store.events(filter: filter)
        printEvents(events, json: output.json, plain: output.plain)
    }
}

// MARK: - Event All

struct EventAll: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "all",
        abstract: "Show all events"
    )

    @Option(name: .long, help: "Start date (default: today)")
    var from: String?

    @Option(name: .long, help: "End date")
    var to: String?

    @Option(name: .long, help: "Number of days")
    var days: Int?

    @Option(name: [.short, .long], help: "Search text")
    var search: String?

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()

        let startDate = from.flatMap { parseDate($0) } ?? Calendar.current.startOfDay(for: Date())
        let endDate: Date
        if let toStr = to, let parsed = parseDate(toStr) {
            endDate = parsed
        } else if let d = days {
            endDate = Calendar.current.date(byAdding: .day, value: d, to: startDate)!
        } else {
            endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate)!
        }

        let filter = EventFilter(
            startDate: startDate,
            endDate: endDate,
            searchText: search
        )

        let events = try await store.events(filter: filter)
        printEvents(events, json: output.json, plain: output.plain)
    }
}

// MARK: - Event Edit

struct EventEdit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit an event"
    )

    @Argument(help: "Event ID")
    var id: String

    @Option(name: [.short, .long], help: "New title")
    var title: String?

    @Option(name: .long, help: "New start date/time")
    var start: String?

    @Option(name: .long, help: "New end date/time")
    var end: String?

    @Option(name: [.short, .long], help: "New duration")
    var duration: String?

    @Option(name: [.short, .long], help: "New location")
    var location: String?

    @Option(name: .long, help: "New URL")
    var url: String?

    @Option(name: [.short, .long], help: "New notes")
    var notes: String?

    @Flag(name: .long, help: "Clear all alarms")
    var clearAlarms = false

    @Option(name: .long, help: "Add alarm")
    var alarm: [String] = []

    @Flag(name: .long, help: "Clear recurrence")
    var clearRecurrence = false

    @Option(name: .long, help: "Set recurrence")
    var recurrence: String?

    @Option(name: .long, help: "Recurrence interval")
    var interval: Int?

    @Flag(name: .long, help: "Apply to all future events (for recurring)")
    var futureEvents = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()

        var update = EventUpdate(
            title: title,
            notes: notes,
            location: location,
            url: url.flatMap { URL(string: $0) },
            startDate: start.flatMap { parseDate($0) },
            clearAlarms: clearAlarms,
            alarms: alarm
        )

        // Handle end date / duration
        if let endStr = end {
            update.endDate = parseDate(endStr)
        } else if let durationStr = duration, let startDate = update.startDate {
            if let seconds = parseDuration(durationStr) {
                update.endDate = startDate.addingTimeInterval(seconds)
            }
        }

        // Handle recurrence
        if clearRecurrence {
            update.recurrence = .clear
        } else if let recStr = recurrence {
            if let rule = parseRecurrence(recStr, interval: interval) {
                update.recurrence = .set(rule)
            }
        }

        let span: EKSpan = futureEvents ? .futureEvents : .thisEvent
        let event = try await store.updateEvent(id: id, update: update, span: span)

        if output.json {
            print(event.toJSON())
        } else {
            print("✓ Updated: \(event.title)")
        }
    }
}

// MARK: - Event Delete

struct EventDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete an event"
    )

    @Argument(help: "Event ID(s)")
    var ids: [String]

    @Flag(name: .long, help: "Delete all occurrences (for recurring)")
    var all = false

    @Flag(name: .long, help: "Skip confirmation")
    var force = false

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()

        let span: EKSpan = all ? .futureEvents : .thisEvent

        for id in ids {
            let title = try await store.deleteEvent(id: id, span: span)
            print("✓ Deleted: \(title)")
        }
    }
}

// MARK: - Event Copy

struct EventCopy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "copy",
        abstract: "Copy an event to another calendar"
    )

    @Argument(help: "Event ID")
    var id: String

    @Option(name: .long, help: "Target calendar name")
    var to: String

    @Option(name: .long, help: "New start date/time")
    var start: String?

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()

        let newStart = start.flatMap { parseDate($0) }
        let event = try await store.copyEvent(id: id, toCalendar: to, newStartDate: newStart)

        if output.json {
            print(event.toJSON())
        } else {
            print("✓ Copied to [\(event.calendarName)]: \(event.title)")
        }
    }
}

// MARK: - Event Skip

struct EventSkip: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skip",
        abstract: "Skip a recurring event occurrence"
    )

    @Argument(help: "Event ID")
    var id: String

    @Option(name: .long, help: "Date to skip")
    var date: String

    @Option(name: .long, help: "Reason for skipping")
    var reason: String?

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()

        guard let skipDate = parseDate(date) else {
            throw ValidationError("Invalid date: \(date)")
        }

        try await store.skipOccurrence(eventID: id, date: skipDate)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        print("✓ Skipped occurrence on \(formatter.string(from: skipDate))")
        if let reason = reason {
            print("  Reason: \(reason)")
        }
    }
}

// MARK: - Event Modify (single occurrence)

struct EventModify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "modify",
        abstract: "Modify a single occurrence of a recurring event"
    )

    @Argument(help: "Event ID")
    var id: String

    @Option(name: .long, help: "Date of the occurrence to modify")
    var date: String

    @Option(name: .long, help: "New start time")
    var start: String?

    @Option(name: .long, help: "New end time")
    var end: String?

    @Option(name: [.short, .long], help: "New title")
    var title: String?

    @Option(name: [.short, .long], help: "New location")
    var location: String?

    @Option(name: [.short, .long], help: "New notes")
    var notes: String?

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()

        guard let occDate = parseDate(date) else {
            throw ValidationError("Invalid date: \(date)")
        }

        let update = EventUpdate(
            title: title,
            notes: notes,
            location: location,
            startDate: start.flatMap { parseDate($0) },
            endDate: end.flatMap { parseDate($0) }
        )

        let event = try await store.modifyOccurrence(eventID: id, date: occDate, update: update)

        if output.json {
            print(event.toJSON())
        } else {
            print("✓ Modified occurrence: \(event.title)")
        }
    }
}

// MARK: - Event Instances

struct EventInstances: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "instances",
        abstract: "List occurrences of a recurring event"
    )

    @Argument(help: "Event ID")
    var id: String

    @Option(name: .long, help: "Start date")
    var from: String?

    @Option(name: .long, help: "End date")
    var to: String?

    @Option(name: .long, help: "Maximum number of instances")
    var limit: Int = 20

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()

        let startDate = from.flatMap { parseDate($0) }
        let endDate = to.flatMap { parseDate($0) }

        let instances = try await store.listOccurrences(
            eventID: id,
            from: startDate,
            to: endDate,
            limit: limit
        )

        if output.json {
            print(toJSON(instances))
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            for (i, instance) in instances.enumerated() {
                var line = "\(i): \(formatter.string(from: instance.startDate))"
                if instance.isModified {
                    line += " [modified]"
                }
                print(line)
            }

            if instances.isEmpty {
                print("No upcoming occurrences found.")
            }
        }
    }
}

// MARK: - Calendar Management Commands

struct Cal: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cal",
        abstract: "Manage calendars",
        subcommands: [
            CalList.self,
            CalCreate.self,
            CalRename.self,
            CalDelete.self,
        ],
        defaultSubcommand: CalList.self,
        aliases: ["c"]
    )
}

struct CalList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all calendars"
    )

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()
        let calendars = await store.calendars()

        if output.json {
            print(toJSON(calendars))
        } else {
            for cal in calendars {
                var flags: [String] = []
                if cal.isSubscribed { flags.append("subscribed") }
                if !cal.allowsModifications { flags.append("read-only") }
                let flagStr = flags.isEmpty ? "" : " (\(flags.joined(separator: ", ")))"
                print("\(cal.title)\(flagStr)")
            }
        }
    }
}

struct CalCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new calendar"
    )

    @Argument(help: "Calendar name")
    var name: String

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()
        let cal = try await store.createCalendar(name: name)
        print("✓ Created calendar: \(cal.title)")
    }
}

struct CalRename: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a calendar"
    )

    @Argument(help: "Current name")
    var oldName: String

    @Argument(help: "New name")
    var newName: String

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()
        try await store.renameCalendar(oldName: oldName, newName: newName)
        print("✓ Renamed: \(oldName) → \(newName)")
    }
}

struct CalDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a calendar"
    )

    @Argument(help: "Calendar name")
    var name: String

    @Flag(name: .long, help: "Skip confirmation")
    var force = false

    func run() async throws {
        let store = try await CalendarStore.shared.requestAccess()
        try await store.deleteCalendar(name: name)
        print("✓ Deleted calendar: \(name)")
    }
}

// MARK: - Output Helpers

func printEvents(_ events: [EventItem], json: Bool, plain: Bool) {
    if json {
        print(toJSON(events))
        return
    }

    if plain {
        for event in events {
            let start = event.startDate.ISO8601Format()
            let end = event.endDate.ISO8601Format()
            print("\(event.id)\t\(event.title)\t\(start)\t\(end)\t\(event.calendarName)")
        }
        return
    }

    // Group by date
    let calendar = Calendar.current
    var grouped: [Date: [EventItem]] = [:]

    for event in events {
        let dayStart = calendar.startOfDay(for: event.startDate)
        grouped[dayStart, default: []].append(event)
    }

    let sortedDays = grouped.keys.sorted()

    for day in sortedDays {
        print("\n\(colored("━━━ \(formatDateHeader(day)) ━━━", .bold))")

        let dayEvents = grouped[day]!.sorted { $0.startDate < $1.startDate }
        for event in dayEvents {
            var line = "  "

            if event.isAllDay {
                line += colored("all-day", .dim)
            } else {
                line += event.formattedTime()
            }

            line += "  \(event.title)"
            line += colored(" [\(event.calendarName)]", .dim)

            if let loc = event.location, !loc.isEmpty {
                line += " 📍"
            }
            if !event.alarms.isEmpty {
                line += " 🔔"
            }
            if event.recurrence != nil {
                line += " 🔄"
            }

            print(line)
        }
    }

    if events.isEmpty {
        print("No events found.")
    }
}
