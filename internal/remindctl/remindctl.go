package remindctl

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

const defaultBin = "remindctl"

// Reminder represents a single reminder from remindctl.
type Reminder struct {
	ID             string `json:"id"`
	Title          string `json:"title"`
	DueDate        string `json:"dueDate,omitempty"`
	IsCompleted    bool   `json:"isCompleted"`
	ListID         string `json:"listID"`
	ListName       string `json:"listName"`
	Priority       string `json:"priority"`
	Notes          string `json:"notes,omitempty"`
	CompletionDate string `json:"completionDate,omitempty"`
}

// ParsedDueDate returns the parsed due date, or zero time if absent/invalid.
func (r Reminder) ParsedDueDate() time.Time {
	if r.DueDate == "" {
		return time.Time{}
	}
	t, err := time.Parse(time.RFC3339, r.DueDate)
	if err != nil {
		return time.Time{}
	}
	return t
}

// HasDueDate returns true if the reminder has a due date.
func (r Reminder) HasDueDate() bool {
	return r.DueDate != ""
}

// IsOverdue returns true if the reminder is past due and not completed.
func (r Reminder) IsOverdue(now time.Time) bool {
	if !r.HasDueDate() || r.IsCompleted {
		return false
	}
	due := r.ParsedDueDate()
	if due.IsZero() {
		return false
	}
	localDue := due.In(now.Location())
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	dueDay := time.Date(localDue.Year(), localDue.Month(), localDue.Day(), 0, 0, 0, 0, now.Location())
	return dueDay.Before(today)
}

// IsDueToday returns true if the reminder is due today.
func (r Reminder) IsDueToday(now time.Time) bool {
	if !r.HasDueDate() || r.IsCompleted {
		return false
	}
	due := r.ParsedDueDate()
	if due.IsZero() {
		return false
	}
	localDue := due.In(now.Location())
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	dueDay := time.Date(localDue.Year(), localDue.Month(), localDue.Day(), 0, 0, 0, 0, now.Location())
	return dueDay.Equal(today)
}

// ReminderList represents a reminder list from remindctl.
type ReminderList struct {
	ID            string `json:"id"`
	Title         string `json:"title"`
	ReminderCount int    `json:"reminderCount"`
	OverdueCount  int    `json:"overdueCount"`
}

// Client wraps the remindctl CLI.
type Client struct {
	bin string
}

// New creates a new remindctl client. If bin is empty, uses PATH lookup.
func New(bin string) *Client {
	if bin == "" {
		bin = defaultBin
	}
	return &Client{bin: bin}
}

// run executes a remindctl command and returns stdout.
func (c *Client) run(args ...string) ([]byte, error) {
	cmd := exec.Command(c.bin, args...)
	out, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("remindctl %s: %s", strings.Join(args, " "), string(exitErr.Stderr))
		}
		return nil, fmt.Errorf("remindctl %s: %w", strings.Join(args, " "), err)
	}
	return out, nil
}

// ShowAll returns all reminders (completed and incomplete).
func (c *Client) ShowAll() ([]Reminder, error) {
	out, err := c.run("show", "all", "--json")
	if err != nil {
		return nil, err
	}
	return ParseReminders(out)
}

// ListLists returns all reminder lists.
func (c *Client) ListLists() ([]ReminderList, error) {
	out, err := c.run("list", "--json")
	if err != nil {
		return nil, err
	}
	return ParseLists(out)
}

// Complete marks a reminder as completed by ID prefix.
func (c *Client) Complete(idPrefix string) error {
	_, err := c.run("complete", idPrefix)
	return err
}

// Add creates a new reminder.
func (c *Client) Add(title, list, due, priority, notes string) error {
	args := []string{"add", title}
	if list != "" {
		args = append(args, "--list", list)
	}
	if due != "" {
		args = append(args, "--due", due)
	}
	if priority != "" && priority != "none" {
		args = append(args, "--priority", priority)
	}
	if notes != "" {
		args = append(args, "--notes", notes)
	}
	_, err := c.run(args...)
	return err
}

// Edit modifies an existing reminder by ID prefix.
func (c *Client) Edit(idPrefix string, title, due, priority, notes string) error {
	args := []string{"edit", idPrefix}
	if title != "" {
		args = append(args, "--title", title)
	}
	if due != "" {
		args = append(args, "--due", due)
	}
	if priority != "" {
		args = append(args, "--priority", priority)
	}
	if notes != "" {
		args = append(args, "--notes", notes)
	}
	if len(args) == 2 {
		return nil // nothing to edit
	}
	_, err := c.run(args...)
	return err
}

// Delete removes a reminder by ID prefix (force, no confirmation).
func (c *Client) Delete(idPrefix string) error {
	_, err := c.run("delete", idPrefix, "--force")
	return err
}

// ParseReminders parses JSON output from remindctl show.
func ParseReminders(data []byte) ([]Reminder, error) {
	var reminders []Reminder
	if err := json.Unmarshal(data, &reminders); err != nil {
		return nil, fmt.Errorf("parsing reminders: %w", err)
	}
	return reminders, nil
}

// ParseLists parses JSON output from remindctl list.
func ParseLists(data []byte) ([]ReminderList, error) {
	var lists []ReminderList
	if err := json.Unmarshal(data, &lists); err != nil {
		return nil, fmt.Errorf("parsing lists: %w", err)
	}
	return lists, nil
}
