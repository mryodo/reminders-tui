// Package icalbuddy shells out to the icalBuddy CLI
// (https://github.com/icalBuddy/icalBuddy) to read events from Apple
// Calendar. icalBuddy already wraps EventKit, so this package -- like
// remindctl for Reminders -- needs no CGo or direct EventKit bindings.
package icalbuddy

import (
	"errors"
	"os/exec"
	"regexp"
	"sort"
	"strings"
	"time"
)

const defaultBin = "icalBuddy"

// bullet prefixes every printed event, and fieldSep separates its
// properties (datetime, title, location) on a single line. -ps requires the
// separator value bracketed by a delimiter character (here "|"), see
// `man icalBuddy`.
const bullet = "@@@ "
const fieldSep = ":::"

// Event represents a single calendar event occurring today.
type Event struct {
	Title    string
	Location string
	AllDay   bool
	Start    time.Time
	End      time.Time
}

// Client wraps the icalBuddy CLI.
type Client struct {
	bin string
}

// New creates a new icalBuddy client. If bin is empty, uses PATH lookup.
func New(bin string) *Client {
	if bin == "" {
		bin = defaultBin
	}
	return &Client{bin: bin}
}

// Available reports whether the icalBuddy binary can be found.
func (c *Client) Available() bool {
	_, err := exec.LookPath(c.bin)
	return err == nil
}

// TodayEvents returns today's calendar events, sorted with all-day events
// first, then timed events in start order.
func (c *Client) TodayEvents(now time.Time) ([]Event, error) {
	return c.EventsOn(now)
}

// EventsOn returns the calendar events on day's date, sorted like
// TodayEvents. -nrd and an empty -df strip the date from the datetime
// field, so the output parses exactly like eventsToday.
func (c *Client) EventsOn(day time.Time) ([]Event, error) {
	date := day.Format("2006-01-02")
	out, err := exec.Command(c.bin,
		"-nc", "-npn", "-nrd",
		"-df", "",
		"-tf", "%H:%M",
		"-iep", "datetime,title,location",
		"-po", "datetime,title,location",
		"-b", bullet,
		"-ps", "|"+fieldSep+"|",
		"eventsFrom:"+date, "to:"+date,
	).Output()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return nil, errors.New(strings.TrimSpace(string(exitErr.Stderr)))
		}
		return nil, err
	}
	return parseEvents(string(out), day), nil
}

// timeRangeRe matches icalBuddy's "-tf %H:%M" time range, e.g. "09:00 - 10:30".
var timeRangeRe = regexp.MustCompile(`^(\d{1,2}:\d{2}) - (\d{1,2}:\d{2})$`)

func parseEvents(out string, now time.Time) []Event {
	var events []Event
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(strings.TrimPrefix(line, strings.TrimRight(bullet, " ")))
		if line == "" {
			continue
		}
		parts := strings.Split(line, fieldSep)
		for i := range parts {
			parts[i] = strings.TrimSpace(parts[i])
		}

		var ev Event
		if m := timeRangeRe.FindStringSubmatch(parts[0]); m != nil {
			ev.Start = todayAt(m[1], now)
			ev.End = todayAt(m[2], now)
			if len(parts) > 1 {
				ev.Title = parts[1]
			}
			if len(parts) > 2 {
				ev.Location = parts[2]
			}
		} else {
			ev.AllDay = true
			ev.Title = parts[0]
			if len(parts) > 1 {
				ev.Location = parts[1]
			}
		}
		if ev.Title == "" {
			continue
		}
		events = append(events, ev)
	}

	sort.SliceStable(events, func(i, j int) bool {
		if events[i].AllDay != events[j].AllDay {
			return events[i].AllDay
		}
		return events[i].Start.Before(events[j].Start)
	})

	return events
}

func todayAt(hhmm string, now time.Time) time.Time {
	t, err := time.Parse("15:04", hhmm)
	if err != nil {
		return time.Time{}
	}
	y, m, d := now.Date()
	return time.Date(y, m, d, t.Hour(), t.Minute(), 0, 0, now.Location())
}
