package main

import (
	"testing"
	"time"

	"github.com/nodeselector/reminders-tui/internal/icalbuddy"
)

func TestFreeSlots(t *testing.T) {
	d := time.Date(2026, 10, 19, 0, 0, 0, 0, time.UTC)
	ev := func(h1, m1, h2, m2 int) icalbuddy.Event {
		return icalbuddy.Event{Start: at(d, h1, m1), End: at(d, h2, m2)}
	}
	events := []icalbuddy.Event{
		{AllDay: true},
		ev(9, 0, 10, 0),   // overlaps window start
		ev(10, 0, 10, 45), // back-to-back
		ev(10, 30, 11, 0), // overlapping
		ev(12, 0, 13, 0),
		ev(16, 0, 17, 0), // overlaps window end
	}
	got := freeSlots(events, at(d, 9, 30), at(d, 16, 30))
	want := []slot{{at(d, 11, 0), at(d, 12, 0)}, {at(d, 13, 0), at(d, 16, 0)}}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if !got[i].start.Equal(want[i].start) || !got[i].end.Equal(want[i].end) {
			t.Errorf("slot %d = %v, want %v", i, got[i], want[i])
		}
	}
}
