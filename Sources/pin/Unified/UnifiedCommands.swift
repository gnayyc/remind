import ArgumentParser
import Foundation

// MARK: - Today Command

struct Today: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show today's events and reminders"
    )

    @Option(name: [.short, .long], help: "Filter by calendar name")
    var calendar: String?

    @Option(name: [.short, .long], help: "Filter by reminder list")
    var list: String?

    @Flag(name: .long, help: "Show only events")
    var eventsOnly = false

    @Flag(name: .long, help: "Show only reminders")
    var remindersOnly = false

    @Flag(name: .long, help: "Include completed reminders")
    var includeCompleted = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart)!

        try await showUnified(
            from: todayStart,
            to: todayEnd,
            calendarName: calendar,
            listName: list,
            eventsOnly: eventsOnly,
            remindersOnly: remindersOnly,
            includeCompleted: includeCompleted,
            json: output.json
        )
    }
}

// MARK: - Week Command

struct Week: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show this week's events and reminders"
    )

    @Option(name: [.short, .long], help: "Filter by calendar name")
    var calendar: String?

    @Option(name: [.short, .long], help: "Filter by reminder list")
    var list: String?

    @Flag(name: .long, help: "Show only events")
    var eventsOnly = false

    @Flag(name: .long, help: "Show only reminders")
    var remindersOnly = false

    @Flag(name: .long, help: "Include completed reminders")
    var includeCompleted = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let weekEnd = cal.date(byAdding: .day, value: 7, to: todayStart)!

        try await showUnified(
            from: todayStart,
            to: weekEnd,
            calendarName: calendar,
            listName: list,
            eventsOnly: eventsOnly,
            remindersOnly: remindersOnly,
            includeCompleted: includeCompleted,
            json: output.json
        )
    }
}

// MARK: - Agenda Command

struct Agenda: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show events and reminders in a date range"
    )

    @Option(name: .long, help: "Start date (default: today)")
    var from: String?

    @Option(name: .long, help: "End date")
    var to: String?

    @Option(name: .long, help: "Number of days to show")
    var days: Int?

    @Option(name: [.short, .long], help: "Filter by calendar name")
    var calendar: String?

    @Option(name: [.short, .long], help: "Filter by reminder list")
    var list: String?

    @Flag(name: .long, help: "Show only events")
    var eventsOnly = false

    @Flag(name: .long, help: "Show only reminders")
    var remindersOnly = false

    @Flag(name: .long, help: "Include completed reminders")
    var includeCompleted = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let cal = Calendar.current
        let startDate = from.flatMap { parseDate($0) } ?? cal.startOfDay(for: Date())

        let endDate: Date
        if let toStr = to, let parsed = parseDate(toStr) {
            endDate = parsed
        } else if let d = days {
            endDate = cal.date(byAdding: .day, value: d, to: startDate)!
        } else {
            endDate = cal.date(byAdding: .day, value: 7, to: startDate)!
        }

        try await showUnified(
            from: startDate,
            to: endDate,
            calendarName: calendar,
            listName: list,
            eventsOnly: eventsOnly,
            remindersOnly: remindersOnly,
            includeCompleted: includeCompleted,
            json: output.json
        )
    }
}

// MARK: - Unified View Helper

struct UnifiedItem: Codable {
    enum ItemType: String, Codable {
        case event
        case reminder
    }

    let type: ItemType
    let id: String
    let title: String
    let date: Date
    let endDate: Date?
    let isAllDay: Bool
    let isCompleted: Bool?
    let source: String  // calendar name or list name
    let hasAlarm: Bool
    let hasRecurrence: Bool
    let priority: String?
}

private func showUnified(
    from startDate: Date,
    to endDate: Date,
    calendarName: String?,
    listName: String?,
    eventsOnly: Bool,
    remindersOnly: Bool,
    includeCompleted: Bool,
    json: Bool
) async throws {
    var items: [UnifiedItem] = []
    let cal = Calendar.current

    // Fetch events
    if !remindersOnly {
        let calendarStore = try await CalendarStore.shared.requestAccess()
        let filter = EventFilter(
            calendarName: calendarName,
            startDate: startDate,
            endDate: endDate
        )
        let events = try await calendarStore.events(filter: filter)

        for event in events {
            items.append(UnifiedItem(
                type: .event,
                id: event.id,
                title: event.title,
                date: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                isCompleted: nil,
                source: event.calendarName,
                hasAlarm: !event.alarms.isEmpty,
                hasRecurrence: event.recurrence != nil,
                priority: nil
            ))
        }
    }

    // Fetch reminders
    if !eventsOnly {
        let reminderStore = try await RemindersStore.shared.requestAccess()
        let filter = ReminderFilter(
            listName: listName,
            includeCompleted: includeCompleted,
            dueDate: endDate,
            includeOverdue: true
        )
        let reminders = try await reminderStore.reminders(filter: filter)

        for reminder in reminders {
            // Filter by date range
            let reminderDate = reminder.dueDate ?? reminder.startDate ?? Date.distantPast
            if reminderDate >= startDate || reminder.dueDate == nil {
                items.append(UnifiedItem(
                    type: .reminder,
                    id: reminder.id,
                    title: reminder.title,
                    date: reminderDate,
                    endDate: nil,
                    isAllDay: true,
                    isCompleted: reminder.isCompleted,
                    source: reminder.listName,
                    hasAlarm: !reminder.alarms.isEmpty,
                    hasRecurrence: reminder.recurrence != nil,
                    priority: reminder.priority
                ))
            }
        }
    }

    // Sort by date
    items.sort { $0.date < $1.date }

    if json {
        print(toJSON(items))
        return
    }

    // Group by date and display
    var grouped: [Date: [UnifiedItem]] = [:]
    for item in items {
        let dayStart = cal.startOfDay(for: item.date)
        grouped[dayStart, default: []].append(item)
    }

    let sortedDays = grouped.keys.sorted()

    for day in sortedDays {
        print("\n\(colored("━━━ \(formatDateHeader(day)) ━━━", .bold))")

        let dayItems = grouped[day]!

        // Separate events and reminders
        let events = dayItems.filter { $0.type == .event }.sorted { $0.date < $1.date }
        let reminders = dayItems.filter { $0.type == .reminder }

        if !events.isEmpty {
            print(colored("\n📅 Events", .cyan))
            for event in events {
                var line = "  "
                if event.isAllDay {
                    line += colored("all-day  ", .dim)
                } else {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .none
                    formatter.timeStyle = .short
                    let timeStr = formatter.string(from: event.date)
                    if let end = event.endDate {
                        line += "\(timeStr)-\(formatter.string(from: end))  "
                    } else {
                        line += "\(timeStr)       "
                    }
                }
                line += event.title
                line += colored(" [\(event.source)]", .dim)

                if event.hasAlarm { line += " 🔔" }
                if event.hasRecurrence { line += " 🔄" }

                print(line)
            }
        }

        if !reminders.isEmpty {
            print(colored("\n☑️  Reminders (\(reminders.count))", .green))
            for (i, reminder) in reminders.enumerated() {
                var line = "  \(i): "

                if reminder.isCompleted == true {
                    line += "✓ "
                }
                if reminder.priority == "high" {
                    line += "❗ "
                }

                line += reminder.title

                if let dueDate = reminder.date as Date?, dueDate != Date.distantPast {
                    line += colored(" (due \(relativeDate(dueDate)))", .dim)
                }

                if reminder.hasAlarm { line += " 🔔" }
                if reminder.hasRecurrence { line += " 🔄" }

                print(line)
            }
        }
    }

    if items.isEmpty {
        print("No events or reminders found.")
    }
}
