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

Optionally, install [`icalBuddy`](https://github.com/icalBuddy/icalBuddy) to show a "Today's Events" frame from Apple Calendar above every view:

```bash
brew install ical-buddy
```

icalBuddy wraps EventKit itself, so no CGo or direct EventKit integration is needed here -- reminders-tui just shells out to it, the same way it shells out to `remindctl`. If `icalBuddy` isn't installed, the frame is simply omitted and the rest of the app is unaffected.

## Views

| Key | View | Description |
|-----|------|-------------|
| `1` | This Week | Overdue, due this week, or tagged `#thisweek`, grouped by list. New reminders are auto-tagged `#thisweek`. |
| `2` | Today | Due today + overdue, grouped |
| `3` | Upcoming | Next 7 days, grouped by date |
| `4` | Lists | Grouped by list name |
| `5` | All | Flat list, sorted by urgency |

Reminders with notes (including any attached URL, which `remindctl` stores in notes) show their notes wrapped beneath the title, with the `#thisweek` tag hidden since it's an internal marker. Press `n` to toggle between showing notes for every reminder or only the selected one.

Due dates accept `remindctl`'s own formats (`today`, `tomorrow`, `YYYY-MM-DD[ HH:mm]`, ...) plus a few natural shortcuts: weekday names (`friday`, `tue`, ...) resolve to the next occurrence of that weekday (today counts if today is that weekday), and `today`/`tomorrow` can take a time, e.g. `tomorrow 14:00`.

## Keybinds

| Key | Action |
|-----|--------|
| `j` / `k` | Navigate down / up |
| `x` / `Space` | Complete reminder |
| `a` | Add new reminder (step-by-step) |
| `i` | Quick add: `title @list !priority ~due #tag` (list auto-filled if the cursor is inside a list section) |
| `e` | Edit selected reminder |
| `d` | Delete (with confirmation) |
| `Tab` / `1-5` | Switch views |
| `/` | Search / filter |
| `r` | Refresh data |
| `c` | Expand/collapse the Today's Events frame (only when icalBuddy is installed) |
| `n` | Toggle notes display: all reminders / selected reminder only |
| `?` | Help overlay |
| `q` | Quit |

## Architecture

```
main.go                  -- entry point
internal/
  remindctl/             -- CLI wrapper (exec + JSON parse)
    remindctl.go
    remindctl_test.go
  icalbuddy/             -- icalBuddy CLI wrapper for today's calendar events
    icalbuddy.go
    icalbuddy_test.go
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
