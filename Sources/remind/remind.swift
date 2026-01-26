import ArgumentParser
import EventKit
import Foundation

// MARK: - Main CLI

@main
struct Remind: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remind",
        abstract: "Complete CLI for Apple Reminders",
        version: "1.0.0",
        subcommands: [
            Add.self,
            Show.self,
            ShowAll.self,
            Edit.self,
            Complete.self,
            Uncomplete.self,
            Delete.self,
            Lists.self,
            ListCreate.self,
            ListRename.self,
            ListDelete.self,
            Status.self,
        ],
        defaultSubcommand: ShowAll.self
    )
}

// MARK: - Shared Options

struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Output as JSON")
    var json = false
    
    @Flag(name: .long, help: "Output as plain TSV")
    var plain = false
}

struct DateOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "Start date (when to show)")
    var start: String?
    
    @Option(name: [.short, .long], help: "Due date (deadline)")
    var due: String?
    
    @Option(name: [.short, .long], help: "Remind me date/time (notification)")
    var remind: String?
    
    @Option(name: .long, help: "Additional alarm (can specify multiple)")
    var alarm: [String] = []
}

struct RecurrenceOptions: ParsableArguments {
    @Option(name: .long, help: "Repeat: daily, weekly, monthly, yearly")
    var recurrence: String?
    
    @Option(name: .long, help: "Repeat interval (e.g., 2 for every 2 weeks)")
    var interval: Int?
    
    @Option(name: .long, help: "End repeat date")
    var repeatEnd: String?
}

struct LocationOptions: ParsableArguments {
    @Option(name: .long, help: "Location name for geofence reminder")
    var location: String?
    
    @Option(name: .long, help: "Latitude")
    var lat: Double?
    
    @Option(name: .long, help: "Longitude")
    var lon: Double?
    
    @Option(name: .long, help: "Radius in meters (default: 100)")
    var radius: Double?
    
    @Option(name: .long, help: "Trigger: arrive or leave")
    var trigger: String?
}

// MARK: - Add Command

struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a new reminder"
    )
    
    @Argument(help: "Reminder title")
    var title: String
    
    @Option(name: [.short, .long], help: "List name")
    var list: String?
    
    @Option(name: [.short, .long], help: "Notes")
    var notes: String?
    
    @Option(name: [.short, .long], help: "Priority: none, low, medium, high")
    var priority: String?
    
    @Option(name: .long, help: "URL to attach")
    var url: String?
    
    @Flag(name: .long, help: "Mark as flagged")
    var flagged = false
    
    @Option(name: .long, help: "Tags (comma-separated)")
    var tags: String?
    
    @Option(name: .long, help: "Parent reminder ID (for subtask)")
    var parent: String?
    
    @OptionGroup var dateOptions: DateOptions
    @OptionGroup var recurrenceOptions: RecurrenceOptions
    @OptionGroup var locationOptions: LocationOptions
    @OptionGroup var output: OutputOptions
    
    func run() async throws {
        let store = try await RemindersStore.shared.requestAccess()
        
        let defaultList = await store.defaultListName()
        let listName = list ?? defaultList ?? "Reminders"
        
        let reminder = try await store.createReminder(
            title: title,
            listName: listName,
            notes: notes,
            priority: parsePriority(priority),
            url: url.flatMap { URL(string: $0) },
            flagged: flagged,
            tags: tags?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) },
            startDate: dateOptions.start.flatMap { parseDate($0) },
            dueDate: dateOptions.due.flatMap { parseDate($0) },
            remindDate: dateOptions.remind.flatMap { parseDate($0) },
            additionalAlarms: dateOptions.alarm.compactMap { parseDate($0) },
            recurrence: recurrenceOptions.recurrence.flatMap { parseRecurrence($0, interval: recurrenceOptions.interval) },
            recurrenceEnd: recurrenceOptions.repeatEnd.flatMap { parseDate($0) },
            location: parseLocation(locationOptions),
            parentID: parent
        )
        
        if output.json {
            print(reminder.toJSON())
        } else {
            print("✓ \(reminder.title) [\(reminder.listName)] — \(reminder.formattedDates())")
        }
    }
}

// MARK: - Show Command

struct Show: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show reminders in a list"
    )
    
    @Argument(help: "List name")
    var listName: String
    
    @Flag(name: .long, help: "Include completed")
    var includeCompleted = false
    
    @Flag(name: .long, help: "Show only completed")
    var onlyCompleted = false
    
    @Option(name: .long, help: "Filter by due date")
    var dueDate: String?
    
    @Flag(name: .long, help: "Include overdue items")
    var includeOverdue = false
    
    @OptionGroup var output: OutputOptions
    
    func run() async throws {
        let store = try await RemindersStore.shared.requestAccess()
        let filter = ReminderFilter(
            listName: listName,
            includeCompleted: includeCompleted,
            onlyCompleted: onlyCompleted,
            dueDate: dueDate.flatMap { parseDate($0) },
            includeOverdue: includeOverdue
        )
        let reminders = try await store.reminders(filter: filter)
        printReminders(reminders, json: output.json, plain: output.plain)
    }
}

struct ShowAll: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "all",
        abstract: "Show all reminders"
    )
    
    @Flag(name: .long, help: "Include completed")
    var includeCompleted = false
    
    @Option(name: .long, help: "Filter: today, tomorrow, week, overdue")
    var filter: String?
    
    @OptionGroup var output: OutputOptions
    
    func run() async throws {
        let store = try await RemindersStore.shared.requestAccess()
        let dateFilter = parseDateFilter(filter)
        let reminders = try await store.allReminders(
            includeCompleted: includeCompleted,
            dateFilter: dateFilter
        )
        printReminders(reminders, json: output.json, plain: output.plain)
    }
}

// MARK: - Edit Command

struct Edit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Edit a reminder"
    )
    
    @Argument(help: "Reminder ID or index")
    var id: String
    
    @Option(name: [.short, .long], help: "List name (for index lookup)")
    var list: String?
    
    @Option(name: [.short, .long], help: "New title")
    var title: String?
    
    @Option(name: [.short, .long], help: "New notes")
    var notes: String?
    
    @Option(name: [.short, .long], help: "Priority: none, low, medium, high")
    var priority: String?
    
    @Option(name: .long, help: "URL")
    var url: String?
    
    @Flag(name: .long, help: "Set flagged")
    var flagged = false
    
    @Flag(name: .long, help: "Clear flagged")
    var unflagged = false
    
    @Option(name: .long, help: "Tags (comma-separated, replaces existing)")
    var tags: String?
    
    @OptionGroup var dateOptions: DateOptions
    @OptionGroup var recurrenceOptions: RecurrenceOptions
    @OptionGroup var locationOptions: LocationOptions
    
    @Flag(name: .long, help: "Clear start date")
    var clearStart = false
    
    @Flag(name: .long, help: "Clear due date")
    var clearDue = false
    
    @Flag(name: .long, help: "Clear all alarms")
    var clearAlarms = false
    
    @Flag(name: .long, help: "Clear recurrence")
    var clearRecurrence = false
    
    @Flag(name: .long, help: "Clear location")
    var clearLocation = false
    
    @OptionGroup var output: OutputOptions
    
    func run() async throws {
        let store = try await RemindersStore.shared.requestAccess()
        
        let update = ReminderUpdate(
            title: title,
            notes: notes,
            priority: priority.flatMap { parsePriority($0) },
            url: url.flatMap { URL(string: $0) },
            flagged: flagged ? true : (unflagged ? false : nil),
            tags: tags?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) },
            startDate: clearStart ? .clear : dateOptions.start.flatMap { .set(parseDate($0)!) },
            dueDate: clearDue ? .clear : dateOptions.due.flatMap { .set(parseDate($0)!) },
            remindDate: dateOptions.remind.flatMap { .set(parseDate($0)!) },
            clearAlarms: clearAlarms,
            additionalAlarms: dateOptions.alarm.compactMap { parseDate($0) },
            recurrence: clearRecurrence ? .clear : recurrenceOptions.recurrence.flatMap { .set(parseRecurrence($0, interval: recurrenceOptions.interval)!) },
            clearLocation: clearLocation,
            location: parseLocation(locationOptions)
        )
        
        let reminder = try await store.updateReminder(id: id, listName: list, update: update)
        
        if output.json {
            print(reminder.toJSON())
        } else {
            print("✓ Updated: \(reminder.title)")
        }
    }
}

// MARK: - Complete/Uncomplete/Delete Commands

struct Complete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mark reminder(s) as complete"
    )
    
    @Argument(help: "Reminder ID(s) or index(es)")
    var ids: [String]
    
    @Option(name: [.short, .long], help: "List name (for index lookup)")
    var list: String?
    
    func run() async throws {
        let store = try await RemindersStore.shared.requestAccess()
        for id in ids {
            let reminder = try await store.setComplete(true, id: id, listName: list)
            print("✓ Completed: \(reminder.title)")
        }
    }
}

struct Uncomplete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mark reminder(s) as incomplete"
    )
    
    @Argument(help: "Reminder ID(s) or index(es)")
    var ids: [String]
    
    @Option(name: [.short, .long], help: "List name (for index lookup)")
    var list: String?
    
    func run() async throws {
        let store = try await RemindersStore.shared.requestAccess()
        for id in ids {
            let reminder = try await store.setComplete(false, id: id, listName: list)
            print("✓ Uncompleted: \(reminder.title)")
        }
    }
}

struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete reminder(s)"
    )
    
    @Argument(help: "Reminder ID(s) or index(es)")
    var ids: [String]
    
    @Option(name: [.short, .long], help: "List name (for index lookup)")
    var list: String?
    
    @Flag(name: .long, help: "Skip confirmation")
    var force = false
    
    func run() async throws {
        let store = try await RemindersStore.shared.requestAccess()
        for id in ids {
            let title = try await store.deleteReminder(id: id, listName: list)
            print("✓ Deleted: \(title)")
        }
    }
}

// MARK: - List Management Commands

struct Lists: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show all lists"
    )
    
    @OptionGroup var output: OutputOptions
    
    func run() async throws {
        let store = try await RemindersStore.shared.requestAccess()
        let lists = await store.lists()
        
        if output.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(lists)
            print(String(data: data, encoding: .utf8)!)
        } else {
            for list in lists {
                let count = try await store.reminderCount(in: list.title)
                print("\(list.title) — \(count) reminders")
            }
        }
    }
}

struct ListCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-create",
        abstract: "Create a new list"
    )
    
    @Argument(help: "List name")
    var name: String
    
    func run() async throws {
        let store = try await RemindersStore.shared.requestAccess()
        let list = try await store.createList(name: name)
        print("✓ Created list: \(list.title)")
    }
}

struct ListRename: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-rename",
        abstract: "Rename a list"
    )
    
    @Argument(help: "Current name")
    var oldName: String
    
    @Argument(help: "New name")
    var newName: String
    
    func run() async throws {
        let store = try await RemindersStore.shared.requestAccess()
        try await store.renameList(oldName: oldName, newName: newName)
        print("✓ Renamed: \(oldName) → \(newName)")
    }
}

struct ListDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-delete",
        abstract: "Delete a list"
    )
    
    @Argument(help: "List name")
    var name: String
    
    @Flag(name: .long, help: "Skip confirmation")
    var force = false
    
    func run() async throws {
        let store = try await RemindersStore.shared.requestAccess()
        try await store.deleteList(name: name)
        print("✓ Deleted list: \(name)")
    }
}

// MARK: - Status Command

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check authorization status"
    )
    
    func run() async throws {
        let status = RemindersStore.authorizationStatus()
        print("Authorization: \(status)")
        
        if status != "fullAccess" {
            print("\nTo grant access:")
            print("  System Settings → Privacy & Security → Reminders → enable 'remind'")
        }
    }
}
