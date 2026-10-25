package model

import "github.com/charmbracelet/bubbles/key"

type keyMap struct {
	Up       key.Binding
	Down     key.Binding
	Complete key.Binding
	Undo     key.Binding
	Add      key.Binding
	Insert   key.Binding
	Edit     key.Binding
	Delete   key.Binding
	Search   key.Binding
	Refresh  key.Binding
	Calendar key.Binding
	Notes    key.Binding
	Quit     key.Binding
	Help     key.Binding
	Tab      key.Binding
	View1    key.Binding
	View2    key.Binding
	View3    key.Binding
	View4    key.Binding
	View5    key.Binding
	View6    key.Binding
	View7    key.Binding
	View8    key.Binding
	Enter    key.Binding
	Escape   key.Binding
}

var keys = keyMap{
	Up: key.NewBinding(
		key.WithKeys("k", "up"),
		key.WithHelp("k/↑", "up"),
	),
	Down: key.NewBinding(
		key.WithKeys("j", "down"),
		key.WithHelp("j/↓", "down"),
	),
	Complete: key.NewBinding(
		key.WithKeys("x", " "),
		key.WithHelp("x/space", "complete"),
	),
	Undo: key.NewBinding(
		key.WithKeys("u"),
		key.WithHelp("u", "undo complete"),
	),
	Add: key.NewBinding(
		key.WithKeys("a"),
		key.WithHelp("a", "add"),
	),
	Insert: key.NewBinding(
		key.WithKeys("i"),
		key.WithHelp("i", "quick add"),
	),
	Edit: key.NewBinding(
		key.WithKeys("e"),
		key.WithHelp("e", "edit"),
	),
	Delete: key.NewBinding(
		key.WithKeys("d"),
		key.WithHelp("d", "delete"),
	),
	Search: key.NewBinding(
		key.WithKeys("/"),
		key.WithHelp("/", "search"),
	),
	Refresh: key.NewBinding(
		key.WithKeys("r"),
		key.WithHelp("r", "refresh"),
	),
	Calendar: key.NewBinding(
		key.WithKeys("c"),
		key.WithHelp("c", "toggle events"),
	),
	Notes: key.NewBinding(
		key.WithKeys("n"),
		key.WithHelp("n", "toggle notes (all/selected)"),
	),
	Quit: key.NewBinding(
		key.WithKeys("q"),
		key.WithHelp("q", "quit"),
	),
	Help: key.NewBinding(
		key.WithKeys("?"),
		key.WithHelp("?", "help"),
	),
	Tab: key.NewBinding(
		key.WithKeys("tab"),
		key.WithHelp("tab", "next view"),
	),
	View1: key.NewBinding(
		key.WithKeys("1"),
		key.WithHelp("1", "this week"),
	),
	View2: key.NewBinding(
		key.WithKeys("2"),
		key.WithHelp("2", "today"),
	),
	View3: key.NewBinding(
		key.WithKeys("3"),
		key.WithHelp("3", "upcoming"),
	),
	View4: key.NewBinding(
		key.WithKeys("4"),
		key.WithHelp("4", "lists"),
	),
	View5: key.NewBinding(
		key.WithKeys("5"),
		key.WithHelp("5", "teaching"),
	),
	View6: key.NewBinding(
		key.WithKeys("6"),
		key.WithHelp("6", "research"),
	),
	View7: key.NewBinding(
		key.WithKeys("7"),
		key.WithHelp("7", "habits"),
	),
	View8: key.NewBinding(
		key.WithKeys("8"),
		key.WithHelp("8", "tasks"),
	),
	Enter: key.NewBinding(
		key.WithKeys("enter"),
	),
	Escape: key.NewBinding(
		key.WithKeys("esc"),
	),
}
