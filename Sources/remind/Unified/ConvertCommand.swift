import ArgumentParser
import EventKit
import Foundation

// MARK: - Convert Command

struct Convert: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Convert between reminder and event"
    )

    @Argument(help: "Item ID (reminder or event)")
    var id: String

    @Option(name: .long, help: "Convert to: event or reminder")
    var to: String

    // Event-specific options
    @Option(name: [.short, .long], help: "Calendar name (for --to event)")
    var calendar: String?

    @Option(name: [.short, .long], help: "Duration (for --to event, default: 1h)")
    var duration: String?

    // Reminder-specific options
    @Option(name: [.short, .long], help: "List name (for --to reminder)")
    var list: String?

    @Flag(name: .long, help: "Delete original after conversion")
    var deleteOriginal = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let targetType = to.lowercased()

        switch targetType {
        case "event", "e":
            try await convertToEvent()
        case "reminder", "r":
            try await convertToReminder()
        default:
            throw ValidationError("--to must be 'event' or 'reminder'")
        }
    }

    private func convertToEvent() async throws {
        let reminderStore = try await RemindersStore.shared.requestAccess()
        let calendarStore = try await CalendarStore.shared.requestAccess()

        // Find the reminder
        let filter = ReminderFilter(includeCompleted: true)
        let reminders = try await reminderStore.allReminders(includeCompleted: true, dateFilter: nil)

        guard let reminder = reminders.first(where: { $0.id == id }) else {
            throw ValidationError("Reminder not found: \(id)")
        }

        // Determine start date
        let startDate = reminder.dueDate ?? reminder.startDate ?? Date()

        // Determine duration
        let durationSeconds: TimeInterval
        if let durationStr = duration {
            durationSeconds = parseDuration(durationStr) ?? 3600
        } else {
            durationSeconds = 3600  // Default 1 hour
        }
        let endDate = startDate.addingTimeInterval(durationSeconds)

        // Convert alarms
        let alarmStrings = reminder.alarms.map { date -> String in
            let offset = date.timeIntervalSince(startDate)
            if offset < 0 {
                let absOffset = abs(offset)
                if absOffset < 3600 {
                    return "\(Int(absOffset / 60))m"
                } else if absOffset < 86400 {
                    return "\(Int(absOffset / 3600))h"
                } else {
                    return "\(Int(absOffset / 86400))d"
                }
            }
            return date.ISO8601Format()
        }

        // Create the event
        let event = try await calendarStore.createEvent(
            title: reminder.title,
            calendarName: calendar,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            location: reminder.location?.name,
            url: reminder.url.flatMap { URL(string: $0) },
            notes: reminder.notes,
            alarms: alarmStrings,
            recurrence: nil,  // TODO: Convert recurrence
            attendees: nil
        )

        // Delete original if requested
        if deleteOriginal {
            _ = try await reminderStore.deleteReminder(id: id, listName: nil)
        }

        if output.json {
            print(event.toJSON())
        } else {
            print("✓ Converted to event: \(event.title)")
            print("  Calendar: \(event.calendarName)")
            print("  Time: \(event.formattedDateRange())")
            if deleteOriginal {
                print("  Original reminder deleted")
            }
        }
    }

    private func convertToReminder() async throws {
        let calendarStore = try await CalendarStore.shared.requestAccess()
        let reminderStore = try await RemindersStore.shared.requestAccess()

        // Find the event
        let event = try await calendarStore.event(withID: id)

        // Convert alarms to dates
        var alarmDates: [Date] = []
        for alarm in event.alarms {
            switch alarm.type {
            case .absolute:
                if let date = ISO8601DateFormatter().date(from: alarm.value) {
                    alarmDates.append(date)
                }
            case .relative:
                if let offset = Double(alarm.value) {
                    let date = event.startDate.addingTimeInterval(offset)
                    alarmDates.append(date)
                }
            }
        }

        // Create the reminder
        let reminder = try await reminderStore.createReminder(
            title: event.title,
            listName: list ?? "Reminders",
            notes: event.notes,
            priority: .none,
            url: event.url.flatMap { URL(string: $0) },
            flagged: false,
            tags: nil,
            startDate: event.startDate,
            dueDate: event.endDate,
            remindDate: alarmDates.first,
            additionalAlarms: Array(alarmDates.dropFirst()),
            recurrence: nil,  // TODO: Convert recurrence
            recurrenceEnd: nil,
            location: nil,
            parentID: nil
        )

        // Delete original if requested
        if deleteOriginal {
            _ = try await calendarStore.deleteEvent(id: id)
        }

        if output.json {
            print(reminder.toJSON())
        } else {
            print("✓ Converted to reminder: \(reminder.title)")
            print("  List: \(reminder.listName)")
            print("  Due: \(reminder.formattedDates())")
            if deleteOriginal {
                print("  Original event deleted")
            }
        }
    }
}
