package ui

import "github.com/charmbracelet/lipgloss"

// Color palette -- uses the terminal's own ANSI colors (0-15) rather than
// fixed hex values, so the app inherits whichever theme the user's terminal
// is configured with instead of imposing one.
var (
	// Base colors
	ColorFg        lipgloss.TerminalColor = lipgloss.NoColor{}     // terminal default foreground
	ColorFgDim     lipgloss.TerminalColor = lipgloss.ANSIColor(8)  // bright black
	ColorFgMuted   lipgloss.TerminalColor = lipgloss.ANSIColor(7)  // white
	ColorAccent    lipgloss.TerminalColor = lipgloss.ANSIColor(12) // bright blue
	ColorAccentDim lipgloss.TerminalColor = lipgloss.ANSIColor(4)  // blue

	// Priority colors
	ColorHigh   lipgloss.TerminalColor = lipgloss.ANSIColor(1) // red
	ColorMedium lipgloss.TerminalColor = lipgloss.ANSIColor(3) // yellow
	ColorLow    lipgloss.TerminalColor = lipgloss.ANSIColor(6) // cyan
	ColorNone   lipgloss.TerminalColor = lipgloss.ANSIColor(8) // bright black

	// Status colors
	ColorOverdue lipgloss.TerminalColor = lipgloss.ANSIColor(1) // red
	ColorToday   lipgloss.TerminalColor = lipgloss.ANSIColor(2) // green
	ColorSoon    lipgloss.TerminalColor = lipgloss.ANSIColor(3) // yellow
	ColorFuture  lipgloss.TerminalColor = lipgloss.ANSIColor(6) // cyan

	// UI chrome
	ColorBorder    lipgloss.TerminalColor = lipgloss.ANSIColor(8) // bright black
	ColorSelection lipgloss.TerminalColor = lipgloss.ANSIColor(8) // selection background
	ColorSuccess   lipgloss.TerminalColor = lipgloss.ANSIColor(2) // green
	ColorError     lipgloss.TerminalColor = lipgloss.ANSIColor(1) // red

	// List tag colors (rotate through these)
	ListColors = []lipgloss.TerminalColor{
		lipgloss.ANSIColor(5), // magenta
		lipgloss.ANSIColor(4), // blue
		lipgloss.ANSIColor(6), // cyan
		lipgloss.ANSIColor(2), // green
		lipgloss.ANSIColor(3), // yellow
		lipgloss.ANSIColor(9), // bright red
	}
)

// Styles
var (
	// Header
	HeaderStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(ColorFg).
			PaddingLeft(1)

	ViewTitleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(ColorAccent)

	CountStyle = lipgloss.NewStyle().
			Foreground(ColorFgDim)

	// Tab bar
	ActiveTabStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(ColorAccent).
			Underline(true)

	InactiveTabStyle = lipgloss.NewStyle().
				Foreground(ColorFgDim)

	TabSepStyle = lipgloss.NewStyle().
			Foreground(ColorFgDim)

	// Reminder items
	SelectedStyle = lipgloss.NewStyle().
			Background(ColorSelection).
			PaddingLeft(1).
			PaddingRight(1)

	NormalItemStyle = lipgloss.NewStyle().
			PaddingLeft(2)

	TitleStyle = lipgloss.NewStyle().
			Foreground(ColorFg)

	TitleOverdueStyle = lipgloss.NewStyle().
				Foreground(ColorOverdue).
				Bold(true)

	DueDateStyle = lipgloss.NewStyle().
			Foreground(ColorFgMuted)

	DueDateOverdueStyle = lipgloss.NewStyle().
				Foreground(ColorOverdue)

	NotesStyle = lipgloss.NewStyle().
			Foreground(ColorFgDim).
			Italic(true)

	// Group headers
	GroupHeaderStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(ColorAccent).
				PaddingLeft(1).
				MarginTop(1)

	GroupHeaderOverdueStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(ColorOverdue).
				PaddingLeft(1).
				MarginTop(1)

	// Status bar
	StatusBarStyle = lipgloss.NewStyle().
			Foreground(ColorFgDim).
			PaddingLeft(1)

	StatusErrorStyle = lipgloss.NewStyle().
				Foreground(ColorError).
				PaddingLeft(1)

	StatusSuccessStyle = lipgloss.NewStyle().
				Foreground(ColorSuccess).
				PaddingLeft(1)

	// Input
	InputLabelStyle = lipgloss.NewStyle().
			Foreground(ColorAccent).
			Bold(true)

	InputStyle = lipgloss.NewStyle().
			Foreground(ColorFg)

	// Floating add/edit form
	FormBoxStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColorAccentDim).
			Padding(0, 1)

	FormTitleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(ColorAccent)

	FormDoneFieldStyle = lipgloss.NewStyle().
				Foreground(ColorFgDim)

	// Help overlay
	HelpKeyStyle = lipgloss.NewStyle().
			Foreground(ColorAccent).
			Bold(true).
			Width(12)

	HelpDescStyle = lipgloss.NewStyle().
			Foreground(ColorFgMuted)

	HelpTitleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(ColorFg).
			MarginBottom(1)

	// Spinner
	SpinnerStyle = lipgloss.NewStyle().
			Foreground(ColorAccent)

	// Confirmation
	ConfirmStyle = lipgloss.NewStyle().
			Foreground(ColorError).
			Bold(true)

	// Today's Events frame
	EventsFrameStyle = lipgloss.NewStyle().
				Border(lipgloss.RoundedBorder()).
				BorderForeground(ColorAccentDim).
				Padding(0, 1)

	EventsFrameTitleStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(ColorAccent)

	EventTimeStyle = lipgloss.NewStyle().
			Foreground(ColorFgMuted)

	EventAllDayStyle = lipgloss.NewStyle().
				Foreground(ColorFgDim)

	EventLocationStyle = lipgloss.NewStyle().
				Foreground(ColorFgDim).
				Italic(true)
)

// ListTagColor returns a consistent color for a list name.
func ListTagColor(listName string) lipgloss.TerminalColor {
	h := 0
	for _, c := range listName {
		h = h*31 + int(c)
	}
	if h < 0 {
		h = -h
	}
	return ListColors[h%len(ListColors)]
}

// ListTagStyle returns a styled tag for a list name.
func ListTagStyle(listName string) lipgloss.Style {
	return lipgloss.NewStyle().Foreground(ListTagColor(listName))
}
