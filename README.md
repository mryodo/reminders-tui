# reminders-tui

A terminal UI for Apple Reminders, built with [Bubble Tea](https://github.com/charmbracelet/bubbletea) and [Lip Gloss](https://github.com/charmbracelet/lipgloss).

Shells out to [`remindctl`](https://github.com/nodeselector/remindctl) for all data access -- no CGo, no direct EventKit.

## Install

```bash
go install github.com/nodeselector/reminders-tui@latest
```

Or build from source:

```bash
go build -o reminders-tui .
```

Requires `remindctl` in `~/.local/bin/` or on your `PATH`.

## Views

| Key | View | Description |
|-----|------|-------------|
| `1` | This Week | Overdue, due this week, or tagged `#thisweek`, grouped by list. New reminders are auto-tagged `#thisweek`. |
| `2` | Today | Due today + overdue, grouped |
| `3` | Upcoming | Next 7 days, grouped by date |
| `4` | Lists | Grouped by list name |
| `5` | All | Flat list, sorted by urgency |

Reminders with notes (including any attached URL, which `remindctl` stores in notes) show their notes wrapped beneath the title.

## Keybinds

| Key | Action |
|-----|--------|
| `j` / `k` | Navigate down / up |
| `x` / `Space` | Complete reminder |
| `a` | Add new reminder |
| `e` | Edit selected reminder |
| `d` | Delete (with confirmation) |
| `Tab` / `1-5` | Switch views |
| `/` | Search / filter |
| `r` | Refresh data |
| `?` | Help overlay |
| `q` | Quit |

## Architecture

```
main.go                  -- entry point
internal/
  remindctl/             -- CLI wrapper (exec + JSON parse)
    remindctl.go
    remindctl_test.go
  model/                 -- Bubble Tea model, update, view
    model.go
    keys.go
  ui/                    -- styles, formatting helpers
    styles.go
    format.go
    format_test.go
```

## Testing

```bash
go test ./...
```
