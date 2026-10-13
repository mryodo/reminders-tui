package remindctl

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// weekdayNames maps weekday words (full names and common abbreviations) to
// their time.Weekday, for resolving inputs like "friday" or "tue".
var weekdayNames = map[string]time.Weekday{
	"sun": time.Sunday, "sunday": time.Sunday,
	"mon": time.Monday, "monday": time.Monday,
	"tue": time.Tuesday, "tues": time.Tuesday, "tuesday": time.Tuesday,
	"wed": time.Wednesday, "weds": time.Wednesday, "wednesday": time.Wednesday,
	"thu": time.Thursday, "thur": time.Thursday, "thurs": time.Thursday, "thursday": time.Thursday,
	"fri": time.Friday, "friday": time.Friday,
	"sat": time.Saturday, "saturday": time.Saturday,
}

// relativeDueRe matches a weekday name or "today"/"tomorrow", optionally
// followed by an HH:mm time, e.g. "friday", "friday 14:00", "tomorrow 09:30".
var relativeDueRe = regexp.MustCompile(`(?i)^(today|tomorrow|sun|sunday|mon|monday|tue|tues|tuesday|wed|weds|wednesday|thu|thur|thurs|thursday|fri|friday|sat|saturday)(?:\s+(\d{1,2}):(\d{2}))?$`)

// NormalizeDue rewrites human-friendly relative due-date phrases into the
// "YYYY-MM-DD[ HH:mm]" format remindctl's --due flag accepts. It handles
// weekday names ("friday" resolves to the next occurrence of that weekday,
// today included), and "today"/"tomorrow" combined with a time (remindctl
// already understands bare "today"/"tomorrow" itself, so those pass through
// unchanged). Anything that doesn't match a known pattern also passes
// through unchanged for remindctl to interpret or reject.
func NormalizeDue(due string, now time.Time) string {
	trimmed := strings.TrimSpace(due)
	m := relativeDueRe.FindStringSubmatch(trimmed)
	if m == nil {
		return due
	}
	word, hh, mm := strings.ToLower(m[1]), m[2], m[3]

	var target time.Time
	switch word {
	case "today":
		if hh == "" {
			return due
		}
		target = now
	case "tomorrow":
		if hh == "" {
			return due
		}
		target = now.AddDate(0, 0, 1)
	default:
		wd, ok := weekdayNames[word]
		if !ok {
			return due
		}
		offset := (int(wd) - int(now.Weekday()) + 7) % 7
		target = now.AddDate(0, 0, offset)
	}

	if hh == "" {
		return target.Format("2006-01-02")
	}
	hour, herr := strconv.Atoi(hh)
	minute, merr := strconv.Atoi(mm)
	if herr != nil || merr != nil || hour > 23 || minute > 59 {
		return due
	}
	return fmt.Sprintf("%s %02d:%02d", target.Format("2006-01-02"), hour, minute)
}
