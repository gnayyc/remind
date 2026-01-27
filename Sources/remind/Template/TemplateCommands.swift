import ArgumentParser
import EventKit
import Foundation

// MARK: - Template Command Group

struct TemplateCmd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "template",
        abstract: "Manage templates",
        subcommands: [
            TemplateCreate.self,
            TemplateList.self,
            TemplateShow.self,
            TemplateUse.self,
            TemplateDelete.self,
        ],
        defaultSubcommand: TemplateList.self,
        aliases: ["t"]
    )
}

// MARK: - Template Create (Interactive)

struct TemplateCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new template interactively"
    )

    @Option(name: [.short, .long], help: "Template name (skip prompt)")
    var name: String?

    @Option(name: .long, help: "Template type: event or reminder")
    var type: String?

    func run() async throws {
        let store = TemplateStore.shared

        // Get template name
        let templateName: String
        if let n = name {
            templateName = n
        } else {
            print("Template name: ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
                throw ValidationError("Template name is required")
            }
            templateName = input
        }

        // Check if already exists
        if await store.exists(name: templateName) {
            throw TemplateError.alreadyExists(templateName)
        }

        // Get template type
        let templateType: TemplateType
        if let t = type?.lowercased() {
            templateType = t == "reminder" ? .reminder : .event
        } else {
            print("Template type: (1) Event (2) Reminder > ", terminator: "")
            let input = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"
            templateType = input == "2" ? .reminder : .event
        }

        let template: Template
        if templateType == .event {
            template = try createEventTemplate(name: templateName)
        } else {
            template = try createReminderTemplate(name: templateName)
        }

        try await store.save(template)
        print("\n✓ Template saved: ~/.config/remind/templates/\(templateName).yaml")
    }

    private func createEventTemplate(name: String) throws -> Template {
        print("\n=== Event Settings ===")

        // Title
        print("Title [variables: {date}, {week}, {weekday}]: ", terminator: "")
        let title = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !title.isEmpty else {
            throw ValidationError("Title is required")
        }

        // Duration
        print("Duration (e.g., 30m, 1h, 1h30m): ", terminator: "")
        let duration = readLine()?.trimmingCharacters(in: .whitespaces)
        let durationValue = duration?.isEmpty == false ? duration : nil

        // Calendar
        print("Default calendar [leave empty for none]: ", terminator: "")
        let calendar = readLine()?.trimmingCharacters(in: .whitespaces)
        let calendarValue = calendar?.isEmpty == false ? calendar : nil

        // Location
        print("Location: ", terminator: "")
        let location = readLine()?.trimmingCharacters(in: .whitespaces)
        let locationValue = location?.isEmpty == false ? location : nil

        // URL
        print("URL (meeting link, etc.): ", terminator: "")
        let url = readLine()?.trimmingCharacters(in: .whitespaces)
        let urlValue = url?.isEmpty == false ? url : nil

        // Notes
        print("Notes: ", terminator: "")
        let notes = readLine()?.trimmingCharacters(in: .whitespaces)
        let notesValue = notes?.isEmpty == false ? notes : nil

        // Alarms
        print("\n=== Alarm Settings ===")
        print("Alarms (comma-separated, e.g., 15m, 1h, 1d 9:00): ", terminator: "")
        let alarmsInput = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        let alarms = alarmsInput.isEmpty ? nil : alarmsInput.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }

        // Recurrence
        print("\n=== Recurrence Settings ===")
        print("Enable recurrence? (y/n): ", terminator: "")
        let enableRec = readLine()?.lowercased().hasPrefix("y") ?? false

        var recurrence: RecurrenceTemplate? = nil
        if enableRec {
            print("Frequency (daily/weekly/monthly/yearly): ", terminator: "")
            let freq = readLine()?.trimmingCharacters(in: .whitespaces) ?? "weekly"

            print("Interval [1]: ", terminator: "")
            let intervalStr = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
            let interval = Int(intervalStr) ?? 1

            recurrence = RecurrenceTemplate(frequency: freq, interval: interval, end: nil, count: nil)
        }

        return Template(
            name: name,
            type: .event,
            title: title,
            notes: notesValue,
            duration: durationValue,
            calendar: calendarValue,
            location: locationValue,
            url: urlValue,
            alarms: alarms,
            recurrence: recurrence
        )
    }

    private func createReminderTemplate(name: String) throws -> Template {
        print("\n=== Reminder Settings ===")

        // Title
        print("Title [variables: {date}, {week}, {weekday}]: ", terminator: "")
        let title = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !title.isEmpty else {
            throw ValidationError("Title is required")
        }

        // List
        print("List: ", terminator: "")
        let list = readLine()?.trimmingCharacters(in: .whitespaces)
        let listValue = list?.isEmpty == false ? list : nil

        // Notes
        print("Notes: ", terminator: "")
        let notes = readLine()?.trimmingCharacters(in: .whitespaces)
        let notesValue = notes?.isEmpty == false ? notes : nil

        // Priority
        print("Priority (none/low/medium/high) [none]: ", terminator: "")
        let priority = readLine()?.trimmingCharacters(in: .whitespaces)
        let priorityValue = priority?.isEmpty == false ? priority : nil

        // Dates
        print("\n=== Date Settings ===")
        print("Start date (e.g., friday 17:00, or leave empty): ", terminator: "")
        let startDate = readLine()?.trimmingCharacters(in: .whitespaces)
        let startDateValue = startDate?.isEmpty == false ? startDate : nil

        print("Due date (e.g., friday 18:00, or leave empty): ", terminator: "")
        let dueDate = readLine()?.trimmingCharacters(in: .whitespaces)
        let dueDateValue = dueDate?.isEmpty == false ? dueDate : nil

        // Alarms
        print("\n=== Alarm Settings ===")
        print("Alarms (comma-separated, e.g., friday 16:30, 15m): ", terminator: "")
        let alarmsInput = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        let alarms = alarmsInput.isEmpty ? nil : alarmsInput.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }

        // Location reminder
        print("\n=== Location Reminder ===")
        print("Enable location reminder? (y/n): ", terminator: "")
        let enableLoc = readLine()?.lowercased().hasPrefix("y") ?? false

        var locationReminder: LocationReminderTemplate? = nil
        if enableLoc {
            print("Location name: ", terminator: "")
            let locName = readLine()?.trimmingCharacters(in: .whitespaces)

            print("Latitude: ", terminator: "")
            guard let lat = Double(readLine() ?? "") else {
                throw ValidationError("Invalid latitude")
            }

            print("Longitude: ", terminator: "")
            guard let lon = Double(readLine() ?? "") else {
                throw ValidationError("Invalid longitude")
            }

            print("Radius in meters [100]: ", terminator: "")
            let radiusStr = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
            let radius = Double(radiusStr) ?? 100

            print("Trigger (arrive/leave) [arrive]: ", terminator: "")
            let trigger = readLine()?.trimmingCharacters(in: .whitespaces)
            let triggerValue = trigger?.isEmpty == false ? trigger : "arrive"

            locationReminder = LocationReminderTemplate(
                name: locName,
                lat: lat,
                lon: lon,
                radius: radius,
                trigger: triggerValue
            )
        }

        // Recurrence
        print("\n=== Recurrence Settings ===")
        print("Enable recurrence? (y/n): ", terminator: "")
        let enableRec = readLine()?.lowercased().hasPrefix("y") ?? false

        var recurrence: RecurrenceTemplate? = nil
        if enableRec {
            print("Frequency (daily/weekly/monthly/yearly): ", terminator: "")
            let freq = readLine()?.trimmingCharacters(in: .whitespaces) ?? "weekly"

            print("Interval [1]: ", terminator: "")
            let intervalStr = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
            let interval = Int(intervalStr) ?? 1

            recurrence = RecurrenceTemplate(frequency: freq, interval: interval, end: nil, count: nil)
        }

        // Tags
        print("\n=== Tags ===")
        print("Tags (comma-separated): ", terminator: "")
        let tagsInput = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        let tags = tagsInput.isEmpty ? nil : tagsInput.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }

        return Template(
            name: name,
            type: .reminder,
            title: title,
            notes: notesValue,
            list: listValue,
            priority: priorityValue,
            startDate: startDateValue,
            dueDate: dueDateValue,
            tags: tags,
            locationReminder: locationReminder,
            alarms: alarms,
            recurrence: recurrence
        )
    }
}

// MARK: - Template List

struct TemplateList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all templates"
    )

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store = TemplateStore.shared
        let templates = try await store.list()

        if output.json {
            print(toJSON(templates))
            return
        }

        if templates.isEmpty {
            print("No templates found.")
            print("Create one with: remind template create")
            return
        }

        for t in templates {
            var line = "\(t.name)"
            line += colored(" [\(t.type.rawValue)]", .dim)
            line += " — \(t.title)"

            var flags: [String] = []
            if t.hasRecurrence { flags.append("🔄") }
            if t.alarmCount > 0 { flags.append("🔔\(t.alarmCount)") }

            if !flags.isEmpty {
                line += " " + flags.joined(separator: " ")
            }

            print(line)
        }
    }
}

// MARK: - Template Show

struct TemplateShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show template details"
    )

    @Argument(help: "Template name")
    var name: String

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store = TemplateStore.shared
        let template = try await store.load(name: name)

        if output.json {
            print(toJSON(template))
            return
        }

        print("Name: \(template.name)")
        print("Type: \(template.type.rawValue)")
        print("Title: \(template.title)")

        if let notes = template.notes {
            print("Notes: \(notes)")
        }

        if template.type == .event {
            if let duration = template.duration {
                print("Duration: \(duration)")
            }
            if let calendar = template.calendar {
                print("Calendar: \(calendar)")
            }
            if let location = template.location {
                print("Location: \(location)")
            }
            if let url = template.url {
                print("URL: \(url)")
            }
        } else {
            if let list = template.list {
                print("List: \(list)")
            }
            if let priority = template.priority {
                print("Priority: \(priority)")
            }
            if let startDate = template.startDate {
                print("Start Date: \(startDate)")
            }
            if let dueDate = template.dueDate {
                print("Due Date: \(dueDate)")
            }
        }

        if let alarms = template.alarms, !alarms.isEmpty {
            print("Alarms: \(alarms.joined(separator: ", "))")
        }

        if let rec = template.recurrence {
            var recStr = rec.frequency
            if let interval = rec.interval, interval > 1 {
                recStr = "every \(interval) \(rec.frequency)"
            }
            print("Recurrence: \(recStr)")
        }
    }
}

// MARK: - Template Use

struct TemplateUse: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "use",
        abstract: "Create event/reminder from template"
    )

    @Argument(help: "Template name")
    var name: String

    // For events
    @Option(name: .long, help: "Start date/time (required for events)")
    var start: String?

    // Overrides
    @Option(name: [.short, .long], help: "Override calendar/list")
    var calendar: String?

    @Option(name: [.short, .long], help: "Override list (for reminders)")
    var list: String?

    @Option(name: .long, help: "Override title")
    var title: String?

    @Option(name: .long, help: "Override location")
    var location: String?

    @Option(name: .long, help: "Override notes")
    var notes: String?

    // Custom variables
    @Option(name: .long, help: "Custom variable (format: key=value)")
    var `var`: [String] = []

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let templateStore = TemplateStore.shared
        let template = try await templateStore.load(name: name)

        // Parse custom variables
        var customVars: [String: String] = [:]
        for v in `var` {
            let parts = v.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                customVars[String(parts[0])] = String(parts[1])
            }
        }

        let variables = TemplateVariables(
            date: start.flatMap { parseDate($0) } ?? Date(),
            customVars: customVars
        )

        if template.type == .event {
            try await useEventTemplate(template, variables: variables)
        } else {
            try await useReminderTemplate(template, variables: variables)
        }
    }

    private func useEventTemplate(_ template: Template, variables: TemplateVariables) async throws {
        guard let startStr = start else {
            throw ValidationError("Event template requires --start")
        }
        guard let startDate = parseDate(startStr) else {
            throw ValidationError("Invalid start date: \(startStr)")
        }

        let calendarStore = try await CalendarStore.shared.requestAccess()

        let overrides = EventTemplateOverrides(
            title: title,
            calendar: calendar,
            location: location,
            notes: notes
        )

        let applied = await TemplateStore.shared.applyToEvent(
            template: template,
            startDate: startDate,
            overrides: overrides,
            variables: variables
        )

        // Parse recurrence
        var recurrenceInfo: RecurrenceInfo? = nil
        if let rec = applied.recurrence {
            let freq: EKRecurrenceFrequency
            switch rec.frequency.lowercased() {
            case "daily": freq = .daily
            case "weekly": freq = .weekly
            case "monthly": freq = .monthly
            case "yearly": freq = .yearly
            default: freq = .weekly
            }

            let end: RecurrenceInfo.RecurrenceEnd?
            if let endStr = rec.end, let endDate = parseDate(endStr) {
                end = .date(endDate)
            } else if let count = rec.count {
                end = .count(count)
            } else {
                end = nil
            }

            recurrenceInfo = RecurrenceInfo(frequency: freq, interval: rec.interval ?? 1, end: end)
        }

        let event = try await calendarStore.createEvent(
            title: applied.title,
            calendarName: applied.calendar,
            startDate: applied.startDate,
            endDate: applied.endDate,
            isAllDay: false,
            location: applied.location,
            url: applied.url.flatMap { URL(string: $0) },
            notes: applied.notes,
            alarms: applied.alarms,
            recurrence: recurrenceInfo,
            attendees: nil
        )

        if output.json {
            print(event.toJSON())
        } else {
            print("✓ \(event.title) [\(event.calendarName)] — \(event.formattedDateRange())")
        }
    }

    private func useReminderTemplate(_ template: Template, variables: TemplateVariables) async throws {
        let reminderStore = try await RemindersStore.shared.requestAccess()

        let overrides = ReminderTemplateOverrides(
            title: title,
            list: list ?? calendar,
            notes: notes,
            startDate: start.flatMap { parseDate($0) },
            dueDate: nil
        )

        let applied = await TemplateStore.shared.applyToReminder(
            template: template,
            baseDate: Date(),
            overrides: overrides,
            variables: variables
        )

        // Parse recurrence
        var recurrenceRule: EKRecurrenceRule? = nil
        if let rec = applied.recurrence {
            recurrenceRule = parseRecurrence(rec.frequency, interval: rec.interval)
        }

        // Parse location
        var locationInfo: LocationInfo? = nil
        if let loc = applied.location {
            locationInfo = LocationInfo(
                name: loc.name,
                latitude: loc.lat,
                longitude: loc.lon,
                radius: loc.radius ?? 100,
                proximity: loc.trigger ?? "arrive"
            )
        }

        // Parse alarms to dates
        let alarmDates = applied.alarms.compactMap { parseDate($0) }

        let reminder = try await reminderStore.createReminder(
            title: applied.title,
            listName: applied.list ?? "Reminders",
            notes: applied.notes,
            priority: parsePriority(applied.priority),
            url: nil,
            flagged: applied.flagged,
            tags: applied.tags,
            startDate: applied.startDate,
            dueDate: applied.dueDate,
            remindDate: alarmDates.first,
            additionalAlarms: Array(alarmDates.dropFirst()),
            recurrence: recurrenceRule,
            recurrenceEnd: nil,
            location: locationInfo,
            parentID: nil
        )

        if output.json {
            print(reminder.toJSON())
        } else {
            print("✓ \(reminder.title) [\(reminder.listName)] — \(reminder.formattedDates())")
        }
    }
}

// MARK: - Template Delete

struct TemplateDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a template"
    )

    @Argument(help: "Template name")
    var name: String

    @Flag(name: .long, help: "Skip confirmation")
    var force = false

    func run() async throws {
        let store = TemplateStore.shared
        try await store.delete(name: name)
        print("✓ Deleted template: \(name)")
    }
}
