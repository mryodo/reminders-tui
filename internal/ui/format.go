package ui

import (
	"fmt"
	"math"
	"time"

	"github.com/charmbracelet/lipgloss"
)

// PriorityIndicator returns a colored dot for the priority level.
func PriorityIndicator(priority string) string {
	switch priority {
	case "high":
		return lipgloss.NewStyle().Foreground(ColorHigh).Render("●")
	case "medium":
		return lipgloss.NewStyle().Foreground(ColorMedium).Render("●")
	case "low":
		return lipgloss.NewStyle().Foreground(ColorLow).Render("●")
	default:
		return lipgloss.NewStyle().Foreground(ColorNone).Render("·")
	}
}

// RelativeDate formats a time relative to now.
// Returns human-friendly strings like "today", "tomorrow", "in 3 days",
// "yesterday", "3 days ago", or falls back to absolute "Mon Jan 2".
func RelativeDate(due time.Time, now time.Time) string {
	if due.IsZero() {
		return ""
	}

	localDue := due.In(now.Location())
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	dueDay := time.Date(localDue.Year(), localDue.Month(), localDue.Day(), 0, 0, 0, 0, now.Location())
	diff := dueDay.Sub(today)
	days := int(math.Round(diff.Hours() / 24))

	switch {
	case days == 0:
		return "today"
	case days == 1:
		return "tomorrow"
	case days == -1:
		return "yesterday"
	case days > 1 && days <= 7:
		return fmt.Sprintf("in %d days", days)
	case days < -1 && days >= -7:
		return fmt.Sprintf("%d days ago", -days)
	case days > 7 && days <= 14:
		return "next week"
	default:
		if localDue.Year() == now.Year() {
			return localDue.Format("Mon Jan 2")
		}
		return localDue.Format("Jan 2, 2006")
	}
}

// FormatDueDate returns a styled due date string.
func FormatDueDate(due time.Time, now time.Time) string {
	if due.IsZero() {
		return ""
	}

	rel := RelativeDate(due, now)
	localDue := due.In(now.Location())
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	dueDay := time.Date(localDue.Year(), localDue.Month(), localDue.Day(), 0, 0, 0, 0, now.Location())

	switch {
	case dueDay.Before(today):
		return DueDateOverdueStyle.Render(rel)
	case dueDay.Equal(today):
		return lipgloss.NewStyle().Foreground(ColorToday).Render(rel)
	case dueDay.Before(today.AddDate(0, 0, 3)):
		return lipgloss.NewStyle().Foreground(ColorSoon).Render(rel)
	default:
		return DueDateStyle.Render(rel)
	}
}

// OverdueBadge returns a styled "overdue" badge.
func OverdueBadge() string {
	return lipgloss.NewStyle().
		Foreground(ColorOverdue).
		Bold(true).
		Render("OVERDUE")
}

// Truncate truncates a string to maxLen, adding ellipsis if needed.
func Truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	if maxLen <= 3 {
		return s[:maxLen]
	}
	return s[:maxLen-3] + "..."
}
