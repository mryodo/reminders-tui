package remindctl

import (
	"testing"
	"time"
)

func TestNormalizeDue(t *testing.T) {
	// 2026-09-27 is a Sunday.
	now := time.Date(2026, 9, 27, 10, 0, 0, 0, time.UTC)

	tests := []struct {
		name  string
		input string
		want  string
	}{
		{"bare today passes through", "today", "today"},
		{"bare tomorrow passes through", "tomorrow", "tomorrow"},
		{"today with time", "today 09:30", "2026-09-27 09:30"},
		{"tomorrow with time", "tomorrow 14:00", "2026-09-28 14:00"},
		{"weekday later this week", "friday", "2026-10-02"},
		{"weekday today", "sunday", "2026-09-27"},
		{"weekday abbreviation", "fri", "2026-10-02"},
		{"weekday with time", "friday 14:00", "2026-10-02 14:00"},
		{"weekday case insensitive", "Friday", "2026-10-02"},
		{"unrecognized passes through", "2026-01-03", "2026-01-03"},
		{"invalid time falls back", "friday 25:00", "friday 25:00"},
		{"garbage passes through", "next quarter", "next quarter"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := NormalizeDue(tt.input, now)
			if got != tt.want {
				t.Errorf("NormalizeDue(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}
