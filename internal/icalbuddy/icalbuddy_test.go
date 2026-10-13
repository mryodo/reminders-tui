package icalbuddy

import (
	"testing"
	"time"
)

func TestParseEvents(t *testing.T) {
	now := time.Date(2026, 9, 24, 12, 0, 0, 0, time.UTC)

	out := "@@@ Vacation: Michael\n" +
		"@@@ 18:00 - 20:00:::strickenabend:::Artemis\n" +
		"@@@ 09:00 - 10:00:::Standup\n" +
		"\n"

	events := parseEvents(out, now)
	if len(events) != 3 {
		t.Fatalf("got %d events, want 3", len(events))
	}

	// All-day events sort first.
	if !events[0].AllDay || events[0].Title != "Vacation: Michael" {
		t.Errorf("events[0] = %+v, want all-day Vacation: Michael", events[0])
	}

	// Timed events sort by start time.
	if events[1].AllDay || events[1].Title != "Standup" {
		t.Errorf("events[1] = %+v, want timed Standup at 09:00", events[1])
	}
	if !events[1].Start.Equal(time.Date(2026, 9, 24, 9, 0, 0, 0, time.UTC)) {
		t.Errorf("events[1].Start = %v, want 09:00", events[1].Start)
	}
	if events[1].Location != "" {
		t.Errorf("events[1].Location = %q, want empty", events[1].Location)
	}

	if events[2].Title != "strickenabend" || events[2].Location != "Artemis" {
		t.Errorf("events[2] = %+v, want strickenabend @ Artemis", events[2])
	}
	if !events[2].Start.Equal(time.Date(2026, 9, 24, 18, 0, 0, 0, time.UTC)) {
		t.Errorf("events[2].Start = %v, want 18:00", events[2].Start)
	}
	if !events[2].End.Equal(time.Date(2026, 9, 24, 20, 0, 0, 0, time.UTC)) {
		t.Errorf("events[2].End = %v, want 20:00", events[2].End)
	}
}

func TestParseEventsEmpty(t *testing.T) {
	if events := parseEvents("", time.Now()); len(events) != 0 {
		t.Errorf("got %d events, want 0", len(events))
	}
}
