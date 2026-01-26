# remind

> *"Never forget"* — A complete CLI for Apple Reminders

remind is a powerful command-line interface for Apple Reminders on macOS. Unlike other CLI tools, remind supports **all** reminder features including start dates, multiple alarms, recurring tasks, and location-based reminders.

## Features

| Feature | Support | Example |
|---------|---------|---------|
| Start Date | ✅ | `--start today` |
| Due Date | ✅ | `--due 2026-01-31` |
| Remind Me | ✅ | `--remind "tomorrow 9am"` |
| Multiple Alarms | ✅ | `--alarm "..." --alarm "..."` |
| Recurrence | ✅ | `--recurrence weekly --interval 2` |
| Location-based | ✅ | `--lat 25.0 --lon 121.5 --trigger arrive` |
| Priority | ✅ | `--priority high` |
| URL Attachment | ✅ | `--url https://...` |
| Notes | ✅ | `--notes "Details here"` |
| JSON Output | ✅ | `--json` |

## Installation

### From Source

Requires Xcode Command Line Tools and macOS 14+.

```bash
git clone https://github.com/gnayyc/remind.git
cd remind
swift build -c release
cp .build/release/remind /usr/local/bin/
```

### Homebrew (coming soon)

```bash
brew install gnayyc/tap/remind
```

## Usage

### Add a Reminder

```bash
# Simple
remind add "Buy groceries"

# With dates (this is the killer feature!)
remind add "Submit report" \
  --list "Work" \
  --start "today" \
  --due "2026-01-31" \
  --remind "2026-01-30 09:00"

# With recurrence
remind add "Weekly review" \
  --recurrence weekly \
  --due "next monday"

# With location trigger
remind add "Buy milk" \
  --location "Supermarket" \
  --lat 25.033 \
  --lon 121.565 \
  --radius 200 \
  --trigger arrive
```

### View Reminders

```bash
# Show all incomplete reminders
remind all

# Show reminders in a specific list
remind show "Work"

# Filter by date
remind all --filter today
remind all --filter week

# Include completed
remind show "Work" --include-completed

# JSON output for scripting
remind all --json
```

### Manage Reminders

```bash
# Complete by index
remind complete 0 --list "Work"

# Complete by ID
remind complete ABC123-DEF456

# Edit
remind edit ABC123 --due "tomorrow" --priority high

# Delete
remind delete ABC123 --force
```

### List Management

```bash
# Show all lists
remind lists

# Create a new list
remind list-create "Projects"

# Rename
remind list-rename "Work" "Office"

# Delete
remind list-delete "Old List" --force
```

## Date Formats

remind understands various date formats:

| Format | Example |
|--------|---------|
| Relative | `today`, `tomorrow`, `yesterday` |
| ISO 8601 | `2026-01-31`, `2026-01-31T09:00:00` |
| Date + Time | `2026-01-31 09:00` |
| US Format | `01/31/2026` |
| Relative Time | `in 2 hours`, `in 3 days`, `in 1 week` |
| Next Weekday | `next monday`, `next friday` |
| Time Only | `9am`, `14:30` (assumes today) |

## Why remind?

Existing Apple Reminders CLI tools (`reminders-cli`, `remindctl`) lack support for:
- **Start dates** — when the reminder should appear
- **Custom remind dates** — notification time separate from due date
- **Multiple alarms**

remind fills this gap with complete EventKit integration.

## Requirements

- macOS 14.0 (Sonoma) or later
- Reminders permission (granted on first run)

## Permissions

On first run, remind will request access to Reminders. You can also check status:

```bash
remind status
```

If denied, grant access in:
**System Settings → Privacy & Security → Reminders → enable 'remind'**

## License

MIT

## Author

Built with ❤️ by [gnayyc](https://github.com/gnayyc)
