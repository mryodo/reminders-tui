package model

import (
	"strings"
	"testing"

	"github.com/nodeselector/reminders-tui/internal/remindctl"
)

// TestRenderListShowsPartialItem verifies that when the last item that fits
// in the scroll window doesn't fully fit, renderList shows as much of it as
// the remaining budget allows instead of leaving that room blank.
func TestRenderListShowsPartialItem(t *testing.T) {
	m := Model{width: 40, height: 15, notesShowAll: true}
	m.displayItems = []displayItem{
		{reminder: remindctl.Reminder{ID: "1111111111", Title: "First task", ListName: "Inbox", Priority: "none"}},
		{reminder: remindctl.Reminder{ID: "2222222222", Title: "Second task", ListName: "Inbox", Priority: "none"}},
		{reminder: remindctl.Reminder{
			ID:       "3333333333",
			Title:    "Third task with a long note",
			ListName: "Inbox",
			Priority: "none",
			Notes:    "This is a fairly long note that should wrap across several lines so the item renders as multiple terminal lines here for sure definitely absolutely yes it will wrap.",
		}},
	}
	m.cursor = 0

	out := m.renderList()

	if !strings.Contains(out, "First task") || !strings.Contains(out, "Second task") {
		t.Fatalf("expected both fully-fitting items to render, got:\n%s", out)
	}
	if !strings.Contains(out, "Third task with a long") {
		t.Fatalf("expected the third item to at least partially render instead of being omitted, got:\n%s", out)
	}
	if strings.Contains(out, "definitely absolutely yes it will wrap") {
		t.Fatalf("expected the third item's notes to be clipped by the remaining budget, but the full notes rendered:\n%s", out)
	}
}

func TestStripThisWeekTag(t *testing.T) {
	tests := []struct {
		name  string
		notes string
		want  string
	}{
		{"only the tag", "#thisweek", ""},
		{"tag with other tags on the same line", "#thisweek #urgent", "#urgent"},
		{"tag on its own line among others", "call about contract\n#thisweek", "call about contract"},
		{"case insensitive", "#ThisWeek", ""},
		{"no tag present", "just some notes", "just some notes"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := stripThisWeekTag(tt.notes); got != tt.want {
				t.Errorf("stripThisWeekTag(%q) = %q, want %q", tt.notes, got, tt.want)
			}
		})
	}
}

func TestRenderListNotesToggle(t *testing.T) {
	m := Model{width: 60, height: 30}
	m.displayItems = []displayItem{
		{reminder: remindctl.Reminder{ID: "1111111111", Title: "First task", ListName: "Inbox", Priority: "none", Notes: "note about first"}},
		{reminder: remindctl.Reminder{ID: "2222222222", Title: "Second task", ListName: "Inbox", Priority: "none", Notes: "note about second"}},
	}
	m.cursor = 0

	m.notesShowAll = false
	out := m.renderList()
	if !strings.Contains(out, "note about first") {
		t.Fatalf("expected the selected item's notes to render, got:\n%s", out)
	}
	if strings.Contains(out, "note about second") {
		t.Fatalf("expected the non-selected item's notes to be hidden, got:\n%s", out)
	}

	m.notesShowAll = true
	out = m.renderList()
	if !strings.Contains(out, "note about first") || !strings.Contains(out, "note about second") {
		t.Fatalf("expected notes for both items to render, got:\n%s", out)
	}
}
