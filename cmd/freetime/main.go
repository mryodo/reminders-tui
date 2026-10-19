// Command freetime prints your free slots in Apple Calendar from today
// through Friday, within 09:30-16:30.
package main

import (
	"fmt"
	"os"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/nodeselector/reminders-tui/internal/icalbuddy"
)

// ANSI palette indices, so output follows the terminal's color scheme.
var (
	dayStyle  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("4"))
	timeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("2"))
	durStyle  = lipgloss.NewStyle().Faint(true)
)

type slot struct{ start, end time.Time }

// freeSlots returns the gaps in [from, to] not covered by timed events.
// All-day events are ignored. events must be sorted by start.
func freeSlots(events []icalbuddy.Event, from, to time.Time) []slot {
	var free []slot
	cursor := from
	for _, ev := range events {
		if ev.AllDay || !ev.End.After(cursor) {
			continue
		}
		if ev.Start.After(cursor) {
			free = append(free, slot{cursor, minTime(ev.Start, to)})
		}
		cursor = ev.End
		if !cursor.Before(to) {
			return free
		}
	}
	return append(free, slot{cursor, to})
}

func minTime(a, b time.Time) time.Time {
	if a.Before(b) {
		return a
	}
	return b
}

func at(day time.Time, h, m int) time.Time {
	y, mo, d := day.Date()
	return time.Date(y, mo, d, h, m, 0, 0, day.Location())
}

func main() {
	cal := icalbuddy.New("")
	if !cal.Available() {
		fmt.Fprintln(os.Stderr, "icalBuddy not found (brew install ical-buddy)")
		os.Exit(1)
	}

	now := time.Now()
	for day := now; day.Weekday() >= time.Monday && day.Weekday() <= time.Friday; day = day.AddDate(0, 0, 1) {
		from, to := at(day, 9, 30), at(day, 16, 30)
		if now.After(from) {
			from = now.Truncate(time.Minute)
		}
		if !from.Before(to) {
			continue
		}
		events, err := cal.EventsOn(day)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Println(dayStyle.Render(day.Format("Mon 02 Jan")))
		for _, s := range freeSlots(events, from, to) {
			fmt.Printf("  %s  %s\n",
				timeStyle.Render(s.start.Format("15:04")+" - "+s.end.Format("15:04")),
				durStyle.Render("("+s.end.Sub(s.start).String()+")"))
		}
	}
}
