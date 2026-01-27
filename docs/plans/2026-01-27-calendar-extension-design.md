# Calendar Extension Design

> 擴展 remind CLI 支援 Apple Calendar

## 概述

將現有的 Apple Reminders CLI 擴展為同時支援 Reminders 和 Calendar 的完整工具。

## 命令結構

```
remind                          # 現有提醒功能不變
├── add, show, all, edit, ...   # 提醒事項（維持現狀）
├── lists, list-create, ...     # 提醒清單（維持現狀）
│
├── event (別名: e)             # 日曆事件
│   ├── add                     # 新增事件
│   ├── show <calendar>         # 顯示特定日曆的事件
│   ├── all                     # 所有事件
│   ├── edit <id>               # 編輯事件
│   ├── delete <id>             # 刪除事件
│   ├── copy <id>               # 複製到其他日曆
│   ├── skip <id>               # 跳過重複事件的某一天
│   ├── modify <id>             # 修改重複事件的單一實例
│   └── instances <id>          # 列出重複事件的實例
│
├── cal (別名: c)               # 日曆管理
│   ├── list                    # 列出所有日曆
│   ├── create                  # 建立日曆
│   ├── rename                  # 重新命名
│   └── delete                  # 刪除日曆
│
├── template (別名: t)          # 範本管理
│   ├── create                  # 互動式建立範本
│   ├── list                    # 列出範本
│   ├── show <name>             # 顯示範本內容
│   ├── use <name>              # 用範本建立事件/提醒
│   └── delete <name>           # 刪除範本
│
├── convert <id>                # 轉換提醒↔事件
│
├── today                       # 統一檢視：今天的提醒+事件
├── week                        # 統一檢視：本週
└── agenda                      # 統一檢視：自訂範圍
```

## 事件新增選項

```bash
remind event add "會議標題" \
  # 時間（三種方式擇一）
  --start "2024-01-30 14:00" --end "2024-01-30 15:00"   # 方式1
  --start "2024-01-30 14:00" --duration 1h              # 方式2
  --all-day --date 2024-01-30                           # 方式3

  # 基本屬性
  --calendar "Work"              # 指定日曆
  --location "台北101"           # 地點
  --url "https://meet.google.com/xxx"   # 會議連結
  --notes "討論 Q1 計畫"         # 備註

  # 多重提醒
  --alarm "10m"                  # 10 分鐘前
  --alarm "1h"                   # 1 小時前
  --alarm "1d"                   # 1 天前（同一時間）
  --alarm "1d 9:00"              # 1 天前的早上 9 點
  --alarm "1w"                   # 1 週前
  --alarm "2024-01-29 18:00"     # 指定絕對時間

  # 重複
  --recurrence weekly --interval 2      # 每兩週
  --repeat-end "2024-12-31"             # 重複到年底
  --repeat-count 10                     # 或重複 10 次

  # 參與者（可選）
  --attendee "alice@example.com"

  # 範本
  --template "standup"           # 套用範本

  # 輸出
  --json                         # JSON 格式
```

## 提醒時間格式

| 單位 | 縮寫 | 範例 |
|------|------|------|
| 分鐘 | `m`, `min` | `10m`, `30min` |
| 小時 | `h`, `hr`, `hour` | `1h`, `2hr` |
| 天 | `d`, `day` | `1d`, `3day` |
| 週 | `w`, `wk`, `week` | `1w`, `2wk` |

組合用法：`1d 9:00` (1 天前的 09:00)

## 範本系統

### 儲存位置

`~/.config/remind/templates/<name>.yaml`

### 事件範本

```yaml
name: standup
type: event
title: "Weekly Standup {week}"
duration: 30m
calendar: Work
url: "https://meet.google.com/abc-defg-hij"
alarms:
  - "15m"
  - "5m"
recurrence:
  frequency: weekly
  interval: 1
```

### 提醒範本

```yaml
name: weekly-review
type: reminder
title: "Weekly Review {week}"
list: Work
notes: "檢視本週完成項目，規劃下週"
priority: high
start_date: "friday 17:00"
due_date: "friday 18:00"
alarms:
  - "friday 16:30"
  - "friday 17:00"
recurrence:
  frequency: weekly
  interval: 1
location:                    # 可選
  name: "全聯"
  lat: 25.033
  lon: 121.565
  radius: 100
  trigger: arrive
```

### 範本變數

| 變數 | 說明 | 範例 |
|------|------|------|
| `{date}` | 事件日期 | 2024-01-30 |
| `{week}` | 週數 | W05 |
| `{month}` | 月份 | January |
| `{year}` | 年份 | 2024 |
| `{weekday}` | 星期幾 | Monday |

### 互動式建立

```bash
$ remind template create

範本名稱: standup
範本類型: (1) 事件 (2) 提醒 > 1

=== 事件設定 ===
標題 [可用 {date}, {week} 變數]: Weekly Standup {week}
時長: 30m
預設日曆 [留空不指定]: Work
...

✓ 範本已儲存
```

### 使用範本

```bash
remind template use standup --start "next monday 10:00"
remind template use standup --start "tomorrow 9:00" --calendar "Personal"
remind template use todo-with-location --var item="牛奶"
```

## 複製功能

```bash
remind event copy <id> --to "Personal"
remind event copy <id> --to "Work" --start "tomorrow 10:00"
remind event copy <id> --date "2024-02-05" --to "Personal"  # 複製單一實例
```

## 轉換功能

```bash
# 提醒 → 事件
remind convert <reminder-id> --to event
remind convert <reminder-id> --to event --duration 1h --calendar "Work"

# 事件 → 提醒
remind convert <event-id> --to reminder
remind convert <event-id> --to reminder --list "Work"
```

## 統一檢視

```bash
$ remind today
━━━ 2024-01-30 (週二) ━━━

📅 日曆
  09:00-10:00  Weekly Standup [Work]
  14:00-15:00  1:1 with Alice [Work]

☑️  提醒 (3)
  0: ❗ Submit report (due today)
  1: Buy groceries
  2: Call mom
```

選項：
- `remind today/week/agenda`
- `--calendar`, `--list` 篩選
- `--events-only`, `--reminders-only`
- `--from`, `--to`, `--days` 自訂範圍
- `--json`

## 重複事件操作

```bash
# 跳過特定日期
remind event skip <id> --date "2024-02-05"
remind event skip <id> --date "2024-02-05" --reason "國定假日"

# 修改單一實例
remind event modify <id> --date "2024-02-05" \
  --start "2024-02-05 15:00" --end "2024-02-05 16:00"

# 修改整個系列
remind event edit <id> --location "新會議室"

# 從某日期之後修改
remind event edit <id> --from "2024-02-05" --location "新會議室"

# 列出實例
remind event instances <id>
remind event instances <id> --limit 10
```

## 檔案結構

```
Sources/remind/
├── remind.swift           # 主入口 + 現有提醒命令
├── Store.swift            # 現有 RemindersStore
├── Helpers.swift          # 現有輔助函數
│
├── Calendar/
│   ├── CalendarCommands.swift    # event add/show/edit/delete/copy
│   ├── CalendarStore.swift       # EventKit 日曆操作
│   └── CalendarModels.swift      # EventItem, CalendarList 等
│
├── Template/
│   ├── TemplateCommands.swift    # template create/list/use/delete
│   ├── TemplateStore.swift       # 範本 CRUD
│   └── TemplateModels.swift      # Template struct
│
├── Unified/
│   ├── UnifiedCommands.swift     # today/week/agenda
│   └── ConvertCommand.swift      # convert 命令
│
└── Shared/
    ├── DateParsing.swift         # 日期解析
    ├── AlarmParsing.swift        # 提醒時間解析
    └── OutputFormatting.swift    # 輸出格式化
```

## 依賴

```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),  // YAML
]
```
