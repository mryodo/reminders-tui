package model

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/nodeselector/reminders-tui/internal/icalbuddy"
	"github.com/nodeselector/reminders-tui/internal/remindctl"
	"github.com/nodeselector/reminders-tui/internal/ui"
)

// View represents which view is active.
type View int

const (
	ViewThisWeek View = iota
	ViewToday
	ViewUpcoming
	ViewLists
	ViewTeaching
	ViewResearch
	ViewHabits
	ViewTasks
)

// numViews is the total count of selectable views, used for tab cycling.
const numViews = 8

// teachingLists, researchLists, habitsLists, and tasksLists are the exact
// Reminders.app list titles (including their symbol prefixes) shown as
// sections in the corresponding views.
var teachingLists = []string{"♨︎ Statistics", "✾ I2CN", "✒︎ Thesis", "⛵︎ Seminar", "⛲︎ DPN"}
var researchLists = []string{"☋ Grassman Interpolation", "⚔︎ Joint Sparsification", "⚖︎ Effective Resistances", "⛽︎ GNN convergence"}
var habitsLists = []string{"Habits"}
var tasksLists = []string{"✍︎ Tasks"}

func (v View) String() string {
	switch v {
	case ViewThisWeek:
		return "This Week"
	case ViewToday:
		return "Today"
	case ViewUpcoming:
		return "Upcoming"
	case ViewLists:
		return "Lists"
	case ViewTeaching:
		return "Teaching"
	case ViewResearch:
		return "Research"
	case ViewHabits:
		return "Habits"
	case ViewTasks:
		return "Tasks"
	default:
		return "?"
	}
}

// thisWeekTag is the hashtag used to explicitly pull a reminder into the
// This Week view regardless of its due date. New reminders are tagged with
// it automatically so they show up there by default.
const thisWeekTag = "#thisweek"

// hasThisWeekTag reports whether the reminder is tagged for the This Week
// view via its title or notes.
func hasThisWeekTag(r remindctl.Reminder) bool {
	return strings.Contains(strings.ToLower(r.Title), thisWeekTag) ||
		strings.Contains(strings.ToLower(r.Notes), thisWeekTag)
}

// startOfWeek returns midnight on the Monday of t's week.
func startOfWeek(t time.Time) time.Time {
	offset := int(t.Weekday()) - int(time.Monday)
	if offset < 0 {
		offset += 7
	}
	y, m, d := t.Date()
	return time.Date(y, m, d, 0, 0, 0, 0, t.Location()).AddDate(0, 0, -offset)
}

// Mode represents the current interaction mode.
type Mode int

const (
	ModeNormal Mode = iota
	ModeLoading
	ModeSearch
	ModeInsert // vim-like single-line quick add
	ModeAdd
	ModeAddField // cycling through optional add fields
	ModeEdit
	ModeEditField
	ModeConfirmDelete
	ModeHelp
)

// displayItem is a row in the rendered list -- either a group header or a reminder.
type displayItem struct {
	isHeader bool
	header   string
	overdue  bool // for group header styling
	// sectionList is the reminders-list name this header groups by, set only
	// for headers that represent an actual list (as opposed to headers like
	// "Overdue" or a date label). Used by insert mode to auto-fill the list
	// for a new task when the cursor is inside that section.
	sectionList string
	reminder    remindctl.Reminder
	index       int // index into filtered reminders (only for non-headers)
}

// Model is the top-level Bubble Tea model.
type Model struct {
	client *remindctl.Client

	// Calendar (Today's Events frame). calClient is nil, or Available()
	// returns false, when icalBuddy isn't installed -- the frame is simply
	// omitted in that case.
	calClient    *icalbuddy.Client
	calAvailable bool
	calLoading   bool
	calExpanded  bool // show all events instead of capping at maxEventsShown
	events       []icalbuddy.Event

	// Data
	reminders []remindctl.Reminder
	lists     []remindctl.ReminderList

	// UI state
	view         View
	mode         Mode
	cursor       int           // cursor position in displayItems
	displayItems []displayItem // computed view items
	width        int
	height       int

	// notesShowAll controls whether reminder notes are shown under every
	// item in the list, or only under the currently selected one. Toggled
	// with 'n'.
	notesShowAll bool

	// Search
	searchInput textinput.Model
	searchQuery string

	// Insert mode (vim-like single-line quick add)
	insertInput textinput.Model
	insertList  string // list auto-filled from the cursor's current section, if any

	// Add mode
	addInput    textinput.Model
	addTitle    string
	addList     string
	addDue      string
	addPriority string
	addNotes    string
	addStep     int // 0=title, 1=list, 2=due, 3=priority, 4=notes

	// Edit mode
	editInput     textinput.Model
	editID        string
	editStep      int // 0=title, 1=due, 2=priority, 3=notes
	editTitle     string
	editDue       string
	editPriority  string
	editNotes     string
	editOrigNotes string // reminder's notes at time of edit, prefilled into the notes step

	// Notes field (multi-line, shared by add and edit forms). Plain enter
	// submits the field; shift+enter (or its common terminal fallbacks,
	// ctrl+j and alt+enter) inserts a line break.
	notesArea textarea.Model

	// Status
	statusMsg   string
	statusErr   bool
	statusTimer int // ticks remaining

	// Loading
	spinner spinner.Model
	loading bool

	// completed holds reminders completed this session, most recent last,
	// so 'u' can undo them one at a time.
	completed []remindctl.Reminder

	// Confirm delete
	deleteID    string
	deleteTitle string
}

// Messages
type (
	remindersLoadedMsg struct {
		reminders []remindctl.Reminder
		lists     []remindctl.ReminderList
		err       error
	}
	actionDoneMsg struct {
		msg string
		err error
	}
	statusTickMsg   struct{}
	eventsLoadedMsg struct {
		events []icalbuddy.Event
		err    error
	}
)

// New creates a new model.
func New(client *remindctl.Client, calClient *icalbuddy.Client) Model {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = ui.SpinnerStyle

	si := textinput.New()
	si.Placeholder = "search..."
	si.CharLimit = 100

	ii := textinput.New()
	ii.Placeholder = "new task -- @list !priority ~due #tag"
	ii.CharLimit = 300

	ai := textinput.New()
	ai.Placeholder = "reminder title"
	ai.CharLimit = 200

	ei := textinput.New()
	ei.CharLimit = 200

	na := newNotesArea()

	calAvailable := calClient != nil && calClient.Available()

	return Model{
		client:       client,
		calClient:    calClient,
		calAvailable: calAvailable,
		calLoading:   calAvailable,
		view:         ViewThisWeek,
		mode:         ModeLoading,
		loading:      true,
		spinner:      s,
		searchInput:  si,
		insertInput:  ii,
		addInput:     ai,
		editInput:    ei,
		notesArea:    na,
		width:        80,
		height:       24,
		notesShowAll: true,
	}
}

// newNotesArea builds the multi-line textarea used for editing a reminder's
// notes. Plain enter is left unbound here so the caller can treat it as
// "submit"; shift+enter doesn't reach Bubble Tea as a distinct key on most
// terminals (it requires the Kitty keyboard protocol, which this app doesn't
// enable), so ctrl+j and alt+enter are bound as the widely-supported
// fallbacks for inserting a line break.
func newNotesArea() textarea.Model {
	ta := textarea.New()
	ta.Placeholder = "notes/tags, e.g. #thisweek (enter to keep)"
	ta.ShowLineNumbers = false
	ta.Prompt = ""
	ta.CharLimit = 2000
	ta.SetHeight(3)
	ta.SetWidth(40)
	ta.KeyMap.InsertNewline = key.NewBinding(
		key.WithKeys("shift+enter", "ctrl+j", "alt+enter"),
		key.WithHelp("shift+enter", "line break"),
	)
	ta.FocusedStyle.CursorLine = lipgloss.NewStyle()
	ta.FocusedStyle.Text = lipgloss.NewStyle().Foreground(ui.ColorFg)
	ta.FocusedStyle.Placeholder = lipgloss.NewStyle().Foreground(ui.ColorFgDim)
	ta.BlurredStyle.Text = lipgloss.NewStyle().Foreground(ui.ColorFg)
	ta.BlurredStyle.Placeholder = lipgloss.NewStyle().Foreground(ui.ColorFgDim)
	return ta
}

// Init starts the initial data load.
func (m Model) Init() tea.Cmd {
	cmds := []tea.Cmd{m.spinner.Tick, m.loadData()}
	if m.calAvailable {
		cmds = append(cmds, m.loadEvents())
	}
	return tea.Batch(cmds...)
}

func (m Model) loadData() tea.Cmd {
	return func() tea.Msg {
		reminders, err := m.client.ShowAll()
		if err != nil {
			return remindersLoadedMsg{err: err}
		}
		lists, err := m.client.ListLists()
		if err != nil {
			return remindersLoadedMsg{reminders: reminders, err: err}
		}
		return remindersLoadedMsg{reminders: reminders, lists: lists}
	}
}

// loadEvents fetches today's calendar events via icalBuddy. Errors are
// reported through eventsLoadedMsg but don't block or clear the reminders
// view -- the events frame just stays empty.
func (m Model) loadEvents() tea.Cmd {
	calClient := m.calClient
	return func() tea.Msg {
		events, err := calClient.TodayEvents(time.Now())
		return eventsLoadedMsg{events: events, err: err}
	}
}

func statusTickCmd() tea.Cmd {
	return tea.Tick(time.Second, func(_ time.Time) tea.Msg {
		return statusTickMsg{}
	})
}

// Update handles messages.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		if (m.mode == ModeAddField && m.addStep == 4) || (m.mode == ModeEditField && m.editStep == 3) {
			m.notesArea.SetWidth(m.formContentWidth())
		}
		return m, nil

	case spinner.TickMsg:
		if m.loading {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}
		return m, nil

	case remindersLoadedMsg:
		m.loading = false
		m.mode = ModeNormal
		if msg.err != nil {
			m.statusMsg = fmt.Sprintf("Error: %v", msg.err)
			m.statusErr = true
			m.statusTimer = 5
			// Still use whatever data we got
			if msg.reminders != nil {
				m.reminders = msg.reminders
			}
			m.buildDisplayItems()
			return m, statusTickCmd()
		}
		m.reminders = msg.reminders
		m.lists = msg.lists
		m.buildDisplayItems()
		return m, nil

	case actionDoneMsg:
		if msg.err != nil {
			m.statusMsg = fmt.Sprintf("Error: %v", msg.err)
			m.statusErr = true
			m.statusTimer = 5
			return m, statusTickCmd()
		}
		m.statusMsg = msg.msg
		m.statusErr = false
		m.statusTimer = 3
		// Refresh data after action
		m.loading = true
		return m, tea.Batch(statusTickCmd(), m.loadData(), m.spinner.Tick)

	case eventsLoadedMsg:
		m.calLoading = false
		if msg.err == nil {
			m.events = msg.events
		}
		return m, nil

	case statusTickMsg:
		if m.statusTimer > 0 {
			m.statusTimer--
			if m.statusTimer == 0 {
				m.statusMsg = ""
				m.statusErr = false
			}
			return m, statusTickCmd()
		}
		return m, nil
	}

	// Mode-specific updates
	switch m.mode {
	case ModeSearch:
		return m.updateSearch(msg)
	case ModeInsert:
		return m.updateInsert(msg)
	case ModeAdd:
		return m.updateAdd(msg)
	case ModeAddField:
		return m.updateAddField(msg)
	case ModeEdit:
		return m.updateEdit(msg)
	case ModeEditField:
		return m.updateEditField(msg)
	case ModeConfirmDelete:
		return m.updateConfirmDelete(msg)
	case ModeHelp:
		return m.updateHelp(msg)
	default:
		return m.updateNormal(msg)
	}
}

func (m Model) updateNormal(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, keys.Quit):
			return m, tea.Quit
		case key.Matches(msg, keys.Up):
			m.moveCursor(-1)
		case key.Matches(msg, keys.Down):
			m.moveCursor(1)
		case key.Matches(msg, keys.Complete):
			return m.completeSelected()
		case key.Matches(msg, keys.Undo):
			return m.undoComplete()
		case key.Matches(msg, keys.Add):
			return m.enterAddMode()
		case key.Matches(msg, keys.Insert):
			return m.enterInsertMode()
		case key.Matches(msg, keys.Edit):
			return m.enterEditMode()
		case key.Matches(msg, keys.Delete):
			return m.enterDeleteConfirm()
		case key.Matches(msg, keys.Search):
			return m.enterSearchMode()
		case key.Matches(msg, keys.Refresh):
			m.loading = true
			m.mode = ModeLoading
			cmds := []tea.Cmd{m.loadData(), m.spinner.Tick}
			if m.calAvailable {
				m.calLoading = true
				cmds = append(cmds, m.loadEvents())
			}
			return m, tea.Batch(cmds...)
		case key.Matches(msg, keys.Calendar):
			if m.calAvailable {
				m.calExpanded = !m.calExpanded
			}
		case key.Matches(msg, keys.Notes):
			m.notesShowAll = !m.notesShowAll
		case key.Matches(msg, keys.Help):
			m.mode = ModeHelp
		case key.Matches(msg, keys.Tab):
			m.view = (m.view + 1) % numViews
			m.cursor = 0
			m.buildDisplayItems()
		case key.Matches(msg, keys.View1):
			m.view = ViewThisWeek
			m.cursor = 0
			m.buildDisplayItems()
		case key.Matches(msg, keys.View2):
			m.view = ViewToday
			m.cursor = 0
			m.buildDisplayItems()
		case key.Matches(msg, keys.View3):
			m.view = ViewUpcoming
			m.cursor = 0
			m.buildDisplayItems()
		case key.Matches(msg, keys.View4):
			m.view = ViewLists
			m.cursor = 0
			m.buildDisplayItems()
		case key.Matches(msg, keys.View5):
			m.view = ViewTeaching
			m.cursor = 0
			m.buildDisplayItems()
		case key.Matches(msg, keys.View6):
			m.view = ViewResearch
			m.cursor = 0
			m.buildDisplayItems()
		case key.Matches(msg, keys.View7):
			m.view = ViewHabits
			m.cursor = 0
			m.buildDisplayItems()
		case key.Matches(msg, keys.View8):
			m.view = ViewTasks
			m.cursor = 0
			m.buildDisplayItems()
		}
	}
	return m, nil
}

func (m *Model) moveCursor(delta int) {
	if len(m.displayItems) == 0 {
		return
	}
	m.cursor += delta
	if m.cursor < 0 {
		m.cursor = 0
	}
	if m.cursor >= len(m.displayItems) {
		m.cursor = len(m.displayItems) - 1
	}
	// Skip headers
	if m.displayItems[m.cursor].isHeader {
		m.cursor += delta
		if m.cursor < 0 {
			m.cursor = 0
		}
		if m.cursor >= len(m.displayItems) {
			m.cursor = len(m.displayItems) - 1
		}
	}
}

func (m Model) selectedReminder() (remindctl.Reminder, bool) {
	if m.cursor < 0 || m.cursor >= len(m.displayItems) {
		return remindctl.Reminder{}, false
	}
	item := m.displayItems[m.cursor]
	if item.isHeader {
		return remindctl.Reminder{}, false
	}
	return item.reminder, true
}

func (m Model) completeSelected() (tea.Model, tea.Cmd) {
	r, ok := m.selectedReminder()
	if !ok {
		return m, nil
	}
	m.completed = append(m.completed, r)
	client := m.client
	idPrefix := r.ID[:8]
	title := r.Title
	return m, func() tea.Msg {
		err := client.Complete(idPrefix)
		if err != nil {
			return actionDoneMsg{err: err}
		}
		return actionDoneMsg{msg: fmt.Sprintf("Completed: %s", ui.Truncate(title, 40))}
	}
}

func (m Model) undoComplete() (tea.Model, tea.Cmd) {
	if len(m.completed) == 0 {
		return m, nil
	}
	r := m.completed[len(m.completed)-1]
	m.completed = m.completed[:len(m.completed)-1]
	client := m.client
	return m, func() tea.Msg {
		if err := client.Uncomplete(r.ID[:8]); err != nil {
			return actionDoneMsg{err: err}
		}
		return actionDoneMsg{msg: fmt.Sprintf("Restored: %s", ui.Truncate(r.Title, 40))}
	}
}

// currentSectionList returns the reminders-list name for the section the
// cursor currently sits in (its nearest header at or above the cursor, if
// that header represents an actual list rather than a synthetic group like
// "Overdue" or a date label). Returns "" if the cursor isn't inside a list
// section.
func (m Model) currentSectionList() string {
	for i := m.cursor; i >= 0 && i < len(m.displayItems); i-- {
		if m.displayItems[i].isHeader {
			return m.displayItems[i].sectionList
		}
	}
	return ""
}

// insertFields holds the parsed result of a vim-like quick-add line.
type insertFields struct {
	title    string
	list     string
	priority string
	due      string
	notes    string
}

// insertTokenRe matches the inline field tokens recognized by insert mode:
// @list, !priority, ~due, and #tag. A value may be quoted to include spaces,
// e.g. ~"next monday".
var insertTokenRe = regexp.MustCompile(`(@|!|~|#)(?:"([^"]*)"|(\S+))`)

// parseInsertLine extracts @list, !priority, ~due, and #tag tokens from a
// quick-add line, stripping them out to form the title. Any #tags are joined
// into notes so features like the This Week view's #thisweek tag keep
// working; if the user gave no tags at all, notes default to #thisweek to
// match the same default the step-by-step add form prefills.
func parseInsertLine(line string) insertFields {
	var f insertFields
	var tags []string

	title := insertTokenRe.ReplaceAllStringFunc(line, func(match string) string {
		sub := insertTokenRe.FindStringSubmatch(match)
		value := sub[2]
		if value == "" {
			value = sub[3]
		}
		switch sub[1] {
		case "@":
			f.list = value
		case "!":
			f.priority = value
		case "~":
			f.due = value
		case "#":
			tags = append(tags, "#"+value)
		}
		return ""
	})

	f.title = strings.Join(strings.Fields(title), " ")
	if len(tags) > 0 {
		f.notes = strings.Join(tags, " ")
	} else {
		f.notes = thisWeekTag
	}
	return f
}

func (m Model) enterInsertMode() (tea.Model, tea.Cmd) {
	m.mode = ModeInsert
	m.insertList = m.currentSectionList()
	m.insertInput.SetValue("")
	if m.insertList != "" {
		m.insertInput.Placeholder = fmt.Sprintf("new task in %s -- @list !priority ~due #tag", m.insertList)
	} else {
		m.insertInput.Placeholder = "new task -- @list !priority ~due #tag"
	}
	m.insertInput.Focus()
	return m, m.insertInput.Cursor.BlinkCmd()
}

func (m Model) updateInsert(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, keys.Escape):
			m.mode = ModeNormal
			m.insertInput.Blur()
			return m, nil
		case key.Matches(msg, keys.Enter):
			line := strings.TrimSpace(m.insertInput.Value())
			if line == "" {
				return m, nil
			}
			fields := parseInsertLine(line)
			if fields.title == "" {
				return m, nil
			}
			if fields.list == "" {
				fields.list = m.insertList
			}
			m.insertInput.Blur()
			m.mode = ModeNormal
			return m, m.doInsertAdd(fields)
		}
	}
	var cmd tea.Cmd
	m.insertInput, cmd = m.insertInput.Update(msg)
	return m, cmd
}

func (m Model) doInsertAdd(fields insertFields) tea.Cmd {
	client := m.client
	title := fields.title
	list := fields.list
	due := fields.due
	priority := fields.priority
	notes := fields.notes
	return func() tea.Msg {
		err := client.Add(title, list, due, priority, notes)
		if err != nil {
			return actionDoneMsg{err: err}
		}
		return actionDoneMsg{msg: fmt.Sprintf("Added: %s", ui.Truncate(title, 40))}
	}
}

func (m Model) enterAddMode() (tea.Model, tea.Cmd) {
	m.mode = ModeAdd
	m.addTitle = ""
	m.addList = ""
	m.addDue = ""
	m.addPriority = ""
	m.addNotes = ""
	m.addStep = 0
	m.addInput.SetValue("")
	m.addInput.Placeholder = "reminder title"
	m.addInput.Focus()
	return m, m.addInput.Cursor.BlinkCmd()
}

func (m Model) updateAdd(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, keys.Escape):
			m.mode = ModeNormal
			m.addInput.Blur()
			return m, nil
		case key.Matches(msg, keys.Enter):
			title := strings.TrimSpace(m.addInput.Value())
			if title == "" {
				return m, nil
			}
			m.addTitle = title
			m.addStep = 1
			m.mode = ModeAddField
			m.addInput.SetValue("")
			m.addInput.Placeholder = "list name (enter to skip)"
			return m, nil
		}
	}
	var cmd tea.Cmd
	m.addInput, cmd = m.addInput.Update(msg)
	return m, cmd
}

func (m Model) updateAddField(msg tea.Msg) (tea.Model, tea.Cmd) {
	if m.addStep == 4 {
		return m.updateAddNotes(msg)
	}
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, keys.Escape):
			m.mode = ModeNormal
			m.addInput.Blur()
			return m, nil
		case key.Matches(msg, keys.Enter):
			val := strings.TrimSpace(m.addInput.Value())
			switch m.addStep {
			case 1: // list
				m.addList = val
				m.addStep = 2
				m.addInput.SetValue("")
				m.addInput.Placeholder = "due date, e.g. friday, tomorrow 14:00 (enter to skip)"
				return m, nil
			case 2: // due
				m.addDue = val
				m.addStep = 3
				m.addInput.SetValue("")
				m.addInput.Placeholder = "priority: none/low/medium/high (enter to skip)"
				return m, nil
			case 3: // priority
				m.addPriority = val
				m.addStep = 4
				m.addInput.Blur()
				m.notesArea.SetWidth(m.formContentWidth())
				m.notesArea.SetValue(thisWeekTag)
				m.notesArea.CursorEnd()
				m.notesArea.Focus()
				return m, m.notesArea.Cursor.BlinkCmd()
			}
		}
	}
	var cmd tea.Cmd
	m.addInput, cmd = m.addInput.Update(msg)
	return m, cmd
}

func (m Model) updateAddNotes(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, keys.Escape):
			m.mode = ModeNormal
			m.notesArea.Blur()
			return m, nil
		case key.Matches(msg, keys.Enter):
			m.addNotes = strings.TrimSpace(m.notesArea.Value())
			m.notesArea.Blur()
			m.mode = ModeNormal
			return m, m.doAdd()
		}
	}
	var cmd tea.Cmd
	m.notesArea, cmd = m.notesArea.Update(msg)
	return m, cmd
}

func (m Model) doAdd() tea.Cmd {
	client := m.client
	title := m.addTitle
	list := m.addList
	due := m.addDue
	priority := m.addPriority
	notes := m.addNotes
	return func() tea.Msg {
		err := client.Add(title, list, due, priority, notes)
		if err != nil {
			return actionDoneMsg{err: err}
		}
		return actionDoneMsg{msg: fmt.Sprintf("Added: %s", ui.Truncate(title, 40))}
	}
}

func (m Model) enterEditMode() (tea.Model, tea.Cmd) {
	r, ok := m.selectedReminder()
	if !ok {
		return m, nil
	}
	m.mode = ModeEdit
	m.editID = r.ID[:8]
	m.editStep = 0
	m.editTitle = ""
	m.editDue = ""
	m.editPriority = ""
	m.editNotes = ""
	m.editOrigNotes = r.Notes
	m.editInput.SetValue(r.Title)
	m.editInput.Placeholder = "new title (enter to keep)"
	m.editInput.Focus()
	return m, m.editInput.Cursor.BlinkCmd()
}

func (m Model) updateEdit(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, keys.Escape):
			m.mode = ModeNormal
			m.editInput.Blur()
			return m, nil
		case key.Matches(msg, keys.Enter):
			m.editTitle = strings.TrimSpace(m.editInput.Value())
			m.editStep = 1
			m.mode = ModeEditField
			m.editInput.SetValue("")
			m.editInput.Placeholder = "due date, e.g. friday, tomorrow 14:00 (enter to skip)"
			return m, nil
		}
	}
	var cmd tea.Cmd
	m.editInput, cmd = m.editInput.Update(msg)
	return m, cmd
}

func (m Model) updateEditField(msg tea.Msg) (tea.Model, tea.Cmd) {
	if m.editStep == 3 {
		return m.updateEditNotes(msg)
	}
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, keys.Escape):
			m.mode = ModeNormal
			m.editInput.Blur()
			return m, nil
		case key.Matches(msg, keys.Enter):
			val := strings.TrimSpace(m.editInput.Value())
			switch m.editStep {
			case 1: // due
				m.editDue = val
				m.editStep = 2
				m.editInput.SetValue("")
				m.editInput.Placeholder = "priority: none/low/medium/high (enter to skip)"
				return m, nil
			case 2: // priority
				m.editPriority = val
				m.editStep = 3
				m.editInput.Blur()
				m.notesArea.SetWidth(m.formContentWidth())
				m.notesArea.SetValue(m.editOrigNotes)
				m.notesArea.CursorEnd()
				m.notesArea.Focus()
				return m, m.notesArea.Cursor.BlinkCmd()
			}
		}
	}
	var cmd tea.Cmd
	m.editInput, cmd = m.editInput.Update(msg)
	return m, cmd
}

func (m Model) updateEditNotes(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, keys.Escape):
			m.mode = ModeNormal
			m.notesArea.Blur()
			return m, nil
		case key.Matches(msg, keys.Enter):
			m.editNotes = strings.TrimSpace(m.notesArea.Value())
			m.notesArea.Blur()
			m.mode = ModeNormal
			return m, m.doEdit()
		}
	}
	var cmd tea.Cmd
	m.notesArea, cmd = m.notesArea.Update(msg)
	return m, cmd
}

func (m Model) doEdit() tea.Cmd {
	client := m.client
	id := m.editID
	title := m.editTitle
	due := m.editDue
	priority := m.editPriority
	notes := m.editNotes
	return func() tea.Msg {
		err := client.Edit(id, title, due, priority, notes)
		if err != nil {
			return actionDoneMsg{err: err}
		}
		return actionDoneMsg{msg: "Edited reminder"}
	}
}

func (m Model) enterDeleteConfirm() (tea.Model, tea.Cmd) {
	r, ok := m.selectedReminder()
	if !ok {
		return m, nil
	}
	m.mode = ModeConfirmDelete
	m.deleteID = r.ID[:8]
	m.deleteTitle = r.Title
	return m, nil
}

func (m Model) updateConfirmDelete(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "y", "Y":
			m.mode = ModeNormal
			client := m.client
			id := m.deleteID
			title := m.deleteTitle
			return m, func() tea.Msg {
				err := client.Delete(id)
				if err != nil {
					return actionDoneMsg{err: err}
				}
				return actionDoneMsg{msg: fmt.Sprintf("Deleted: %s", ui.Truncate(title, 40))}
			}
		default:
			m.mode = ModeNormal
		}
	}
	return m, nil
}

func (m Model) enterSearchMode() (tea.Model, tea.Cmd) {
	m.mode = ModeSearch
	m.searchInput.SetValue(m.searchQuery)
	m.searchInput.Focus()
	return m, m.searchInput.Cursor.BlinkCmd()
}

func (m Model) updateSearch(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, keys.Escape):
			m.mode = ModeNormal
			m.searchQuery = ""
			m.searchInput.Blur()
			m.buildDisplayItems()
			return m, nil
		case key.Matches(msg, keys.Enter):
			m.mode = ModeNormal
			m.searchQuery = m.searchInput.Value()
			m.searchInput.Blur()
			m.cursor = 0
			m.buildDisplayItems()
			return m, nil
		}
	}
	var cmd tea.Cmd
	m.searchInput, cmd = m.searchInput.Update(msg)
	// Live filter as user types
	m.searchQuery = m.searchInput.Value()
	m.cursor = 0
	m.buildDisplayItems()
	return m, cmd
}

func (m Model) updateHelp(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		// Any key dismisses help
		_ = msg
		m.mode = ModeNormal
	}
	return m, nil
}

// buildDisplayItems computes the displayItems for the current view.
func (m *Model) buildDisplayItems() {
	now := time.Now()
	incomplete := m.incompleteReminders()

	// Apply search filter
	if m.searchQuery != "" {
		q := strings.ToLower(m.searchQuery)
		var filtered []remindctl.Reminder
		for _, r := range incomplete {
			if strings.Contains(strings.ToLower(r.Title), q) ||
				strings.Contains(strings.ToLower(r.ListName), q) ||
				strings.Contains(strings.ToLower(r.Notes), q) {
				filtered = append(filtered, r)
			}
		}
		incomplete = filtered
	}

	var items []displayItem

	switch m.view {
	case ViewToday:
		items = m.buildTodayItems(incomplete, now)
	case ViewUpcoming:
		items = m.buildUpcomingItems(incomplete, now)
	case ViewLists:
		items = m.buildListsItems(incomplete)
	case ViewTeaching:
		items = m.buildListGroupItems(incomplete, teachingLists)
	case ViewResearch:
		items = m.buildListGroupItems(incomplete, researchLists)
	case ViewHabits:
		items = m.buildListGroupItems(incomplete, habitsLists)
	case ViewTasks:
		items = m.buildListGroupItems(incomplete, tasksLists)
	case ViewThisWeek:
		items = m.buildThisWeekItems(incomplete, now)
	}

	m.displayItems = items

	// Fix cursor bounds
	if m.cursor >= len(m.displayItems) {
		m.cursor = len(m.displayItems) - 1
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
	// Skip header if cursor landed on one
	if len(m.displayItems) > 0 && m.displayItems[m.cursor].isHeader {
		m.moveCursor(1)
	}
}

func (m *Model) incompleteReminders() []remindctl.Reminder {
	var result []remindctl.Reminder
	for _, r := range m.reminders {
		if !r.IsCompleted {
			result = append(result, r)
		}
	}
	return result
}

func (m *Model) buildTodayItems(reminders []remindctl.Reminder, now time.Time) []displayItem {
	var overdue, today, noDue []remindctl.Reminder
	for _, r := range reminders {
		if r.IsOverdue(now) {
			overdue = append(overdue, r)
		} else if r.IsDueToday(now) {
			today = append(today, r)
		} else if !r.HasDueDate() {
			noDue = append(noDue, r)
		}
	}

	sortByPriority(overdue)
	sortByPriority(today)

	var items []displayItem
	if len(overdue) > 0 {
		items = append(items, displayItem{isHeader: true, header: fmt.Sprintf("  Overdue (%d)", len(overdue)), overdue: true})
		for _, r := range overdue {
			items = append(items, displayItem{reminder: r})
		}
	}
	if len(today) > 0 {
		items = append(items, displayItem{isHeader: true, header: fmt.Sprintf("  Due Today (%d)", len(today))})
		for _, r := range today {
			items = append(items, displayItem{reminder: r})
		}
	}
	if len(noDue) > 0 {
		items = append(items, displayItem{isHeader: true, header: fmt.Sprintf("  No Due Date (%d)", len(noDue))})
		for _, r := range noDue {
			items = append(items, displayItem{reminder: r})
		}
	}
	return items
}

func (m *Model) buildUpcomingItems(reminders []remindctl.Reminder, now time.Time) []displayItem {
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	end := today.AddDate(0, 0, 8) // 7 days from tomorrow

	// Group by date
	type dateGroup struct {
		date      time.Time
		reminders []remindctl.Reminder
	}
	groups := make(map[string]*dateGroup)
	var overdue []remindctl.Reminder

	for _, r := range reminders {
		if !r.HasDueDate() {
			continue
		}
		due := r.ParsedDueDate()
		localDue := due.In(now.Location())
		dueDay := time.Date(localDue.Year(), localDue.Month(), localDue.Day(), 0, 0, 0, 0, now.Location())

		if dueDay.Before(today) {
			overdue = append(overdue, r)
			continue
		}
		if dueDay.After(end) || dueDay.Equal(end) {
			continue
		}

		key := dueDay.Format("2006-01-02")
		if _, ok := groups[key]; !ok {
			groups[key] = &dateGroup{date: dueDay}
		}
		groups[key].reminders = append(groups[key].reminders, r)
	}

	// Sort groups by date
	var sortedGroups []*dateGroup
	for _, g := range groups {
		sortedGroups = append(sortedGroups, g)
	}
	sort.Slice(sortedGroups, func(i, j int) bool {
		return sortedGroups[i].date.Before(sortedGroups[j].date)
	})

	var items []displayItem

	if len(overdue) > 0 {
		sortByPriority(overdue)
		items = append(items, displayItem{isHeader: true, header: fmt.Sprintf("  Overdue (%d)", len(overdue)), overdue: true})
		for _, r := range overdue {
			items = append(items, displayItem{reminder: r})
		}
	}

	for _, g := range sortedGroups {
		sortByPriority(g.reminders)
		label := ui.RelativeDate(g.date, now)
		dateStr := g.date.Format("Mon Jan 2")
		if label == "today" || label == "tomorrow" {
			label = strings.ToUpper(label[:1]) + label[1:]
		} else {
			label = dateStr
		}
		items = append(items, displayItem{
			isHeader: true,
			header:   fmt.Sprintf("  %s (%d)", label, len(g.reminders)),
		})
		for _, r := range g.reminders {
			items = append(items, displayItem{reminder: r})
		}
	}

	return items
}

func (m *Model) buildListsItems(reminders []remindctl.Reminder) []displayItem {
	// Group by list name
	type listGroup struct {
		name      string
		reminders []remindctl.Reminder
	}
	groupMap := make(map[string]*listGroup)
	var order []string

	for _, r := range reminders {
		name := r.ListName
		if _, ok := groupMap[name]; !ok {
			groupMap[name] = &listGroup{name: name}
			order = append(order, name)
		}
		groupMap[name].reminders = append(groupMap[name].reminders, r)
	}

	sort.Strings(order)

	var items []displayItem
	for _, name := range order {
		g := groupMap[name]
		sortByPriority(g.reminders)
		items = append(items, displayItem{
			isHeader:    true,
			header:      fmt.Sprintf("  %s (%d)", name, len(g.reminders)),
			sectionList: name,
		})
		for _, r := range g.reminders {
			items = append(items, displayItem{reminder: r})
		}
	}
	return items
}

// buildListGroupItems groups reminders into sections for a fixed, ordered
// set of list names. Lists with no matching reminders are omitted.
func (m *Model) buildListGroupItems(reminders []remindctl.Reminder, listNames []string) []displayItem {
	groupMap := make(map[string][]remindctl.Reminder)
	for _, r := range reminders {
		groupMap[r.ListName] = append(groupMap[r.ListName], r)
	}

	var items []displayItem
	for _, name := range listNames {
		g := groupMap[name]
		if len(g) == 0 {
			continue
		}
		sortByPriority(g)
		items = append(items, displayItem{
			isHeader:    true,
			header:      fmt.Sprintf("  %s (%d)", name, len(g)),
			sectionList: name,
		})
		for _, r := range g {
			items = append(items, displayItem{reminder: r})
		}
	}
	return items
}

// buildThisWeekItems shows reminders due this week (Monday--Sunday) or
// tagged #thisweek, organized into per-list sections. Overdue reminders get
// their own section up top regardless of list.
func (m *Model) buildThisWeekItems(reminders []remindctl.Reminder, now time.Time) []displayItem {
	weekStart := startOfWeek(now)
	weekEnd := weekStart.AddDate(0, 0, 7)

	var overdue []remindctl.Reminder
	var inScope []remindctl.Reminder
	for _, r := range reminders {
		if r.IsOverdue(now) {
			overdue = append(overdue, r)
			continue
		}
		if r.HasDueDate() {
			due := r.ParsedDueDate()
			if !due.Before(weekStart) && due.Before(weekEnd) {
				inScope = append(inScope, r)
				continue
			}
		}
		if hasThisWeekTag(r) {
			inScope = append(inScope, r)
		}
	}

	var items []displayItem
	if len(overdue) > 0 {
		sortByPriority(overdue)
		items = append(items, displayItem{isHeader: true, header: fmt.Sprintf("  Overdue (%d)", len(overdue)), overdue: true})
		for _, r := range overdue {
			items = append(items, displayItem{reminder: r})
		}
	}

	// Group remaining reminders by list name.
	type listGroup struct {
		name      string
		reminders []remindctl.Reminder
	}
	groupMap := make(map[string]*listGroup)
	var order []string
	for _, r := range inScope {
		name := r.ListName
		if _, ok := groupMap[name]; !ok {
			groupMap[name] = &listGroup{name: name}
			order = append(order, name)
		}
		groupMap[name].reminders = append(groupMap[name].reminders, r)
	}
	sort.Strings(order)

	for _, name := range order {
		g := groupMap[name]
		sortByPriority(g.reminders)
		items = append(items, displayItem{
			isHeader:    true,
			header:      fmt.Sprintf("  %s (%d)", name, len(g.reminders)),
			sectionList: name,
		})
		for _, r := range g.reminders {
			items = append(items, displayItem{reminder: r})
		}
	}

	return items
}

func sortByPriority(reminders []remindctl.Reminder) {
	order := map[string]int{"high": 0, "medium": 1, "low": 2, "none": 3, "": 3}
	sort.SliceStable(reminders, func(i, j int) bool {
		return order[reminders[i].Priority] < order[reminders[j].Priority]
	})
}

// View renders the UI.
func (m Model) View() string {
	if m.width == 0 {
		return ""
	}

	var b strings.Builder

	// Today's Events frame sits above every view.
	if frame := m.renderEventsFrame(); frame != "" {
		b.WriteString(frame)
		b.WriteString("\n")
	}

	// Header
	b.WriteString(m.renderHeader())
	b.WriteString("\n")

	// Tab bar
	b.WriteString(m.renderTabBar())
	b.WriteString("\n")

	// Main content
	if m.loading && len(m.reminders) == 0 {
		b.WriteString("  " + m.spinner.View() + " Loading reminders...")
	} else if m.mode == ModeHelp {
		b.WriteString(strings.TrimRight(m.renderHelp(), "\n"))
	} else {
		b.WriteString(strings.TrimRight(m.renderList(), "\n"))
	}

	// Inline bars (search/delete) stay right under the content. Insert
	// mode's bar is rendered inline under the cursor row instead, by
	// renderList itself, so it isn't repeated here.
	if m.mode == ModeSearch {
		b.WriteString("\n")
		b.WriteString(m.renderSearchBar())
	} else if m.mode == ModeConfirmDelete {
		b.WriteString("\n")
		b.WriteString(m.renderDeleteConfirm())
	}

	// Form and status bar are anchored to the bottom; pad only when the
	// content is shorter than the screen (renderList fills it otherwise).
	bottom := "\n" + m.renderStatusBar() // blank line above the status bar
	if form := m.renderForm(); form != "" {
		bottom = form + "\n" + bottom
	}
	lines := strings.Count(b.String(), "\n") + 1
	for i := lines + strings.Count(bottom, "\n") + 1; i < m.height; i++ {
		b.WriteString("\n")
	}
	b.WriteString("\n")
	b.WriteString(bottom)

	return indentLines(b.String(), 1)
}

// indentLines prepends n spaces to every line of s, giving the whole
// rendered view a small left margin.
func indentLines(s string, n int) string {
	pad := strings.Repeat(" ", n)
	lines := strings.Split(s, "\n")
	for i, l := range lines {
		lines[i] = pad + l
	}
	return strings.Join(lines, "\n")
}

// maxEventsShown caps how many events the Today's Events frame displays
// before summarizing the rest, so it doesn't crowd out list content on
// short terminals.
const maxEventsShown = 4

// renderEventsFrame renders the "Today's Events" frame shown above every
// view. It returns "" when icalBuddy isn't installed, so the app looks and
// behaves exactly as it did before this feature existed.
func (m Model) renderEventsFrame() string {
	if !m.calAvailable {
		return ""
	}

	var lines []string
	title := "Today's Events"
	switch {
	case m.calLoading && len(m.events) == 0:
		lines = append(lines, ui.EventAllDayStyle.Render("loading..."))
	case len(m.events) == 0:
		lines = append(lines, ui.EventAllDayStyle.Render("No events today"))
	default:
		shown := m.events
		more := 0
		if !m.calExpanded && len(shown) > maxEventsShown {
			more = len(shown) - maxEventsShown
			shown = shown[:maxEventsShown]
		}
		for _, ev := range shown {
			lines = append(lines, m.renderEventLine(ev))
		}
		if more > 0 {
			lines = append(lines, ui.EventAllDayStyle.Render(fmt.Sprintf("+%d more (c to expand)", more)))
		} else if m.calExpanded && len(m.events) > maxEventsShown {
			title += " (c to collapse)"
		}
	}

	var body strings.Builder
	body.WriteString(ui.EventsFrameTitleStyle.Render(title))
	for _, l := range lines {
		body.WriteString("\n")
		body.WriteString(l)
	}

	return ui.EventsFrameStyle.Width(m.formBoxWidth()).Render(body.String())
}

// renderEventLine renders one calendar event as a single line: its time
// range (or "all day"), title, and location if present.
func (m Model) renderEventLine(ev icalbuddy.Event) string {
	var when string
	if ev.AllDay {
		when = ui.EventAllDayStyle.Render("all day")
	} else {
		when = ui.EventTimeStyle.Render(ev.Start.Format("15:04") + "-" + ev.End.Format("15:04"))
	}

	titleWidth := m.formContentWidth() - lipgloss.Width(when) - 1
	if titleWidth < 10 {
		titleWidth = 10
	}
	title := ui.Truncate(ev.Title, titleWidth)

	line := when + " " + title
	if ev.Location != "" {
		line += ui.EventLocationStyle.Render(" @ " + ev.Location)
	}
	return line
}

func (m Model) renderHeader() string {
	title := ui.ViewTitleStyle.Render("  " + m.view.String())
	count := m.reminderCount()
	countStr := ui.CountStyle.Render(fmt.Sprintf(" (%d)", count))

	search := ""
	if m.searchQuery != "" && m.mode != ModeSearch {
		search = ui.CountStyle.Render(fmt.Sprintf("  filter: %q", m.searchQuery))
	}

	return title + countStr + search
}

func (m Model) reminderCount() int {
	count := 0
	for _, item := range m.displayItems {
		if !item.isHeader {
			count++
		}
	}
	return count
}

const tabBarLeftMargin = "  "

// renderTabBar lays the view tabs out left to right, wrapping onto
// additional lines when they don't all fit within the terminal width.
func (m Model) renderTabBar() string {
	tabs := []struct {
		view View
		key  string
		name string
	}{
		{ViewThisWeek, "1", "This Week"},
		{ViewToday, "2", "Today"},
		{ViewUpcoming, "3", "Upcoming"},
		{ViewLists, "4", "Lists"},
		{ViewTeaching, "5", "Teaching"},
		{ViewResearch, "6", "Research"},
		{ViewHabits, "7", "Habits"},
		{ViewTasks, "8", "Tasks"},
	}

	sep := ui.TabSepStyle.Render(" ")
	sepWidth := lipgloss.Width(sep)
	marginWidth := lipgloss.Width(tabBarLeftMargin)
	maxWidth := m.width
	if maxWidth <= 0 {
		maxWidth = 80
	}

	var lines []string
	var cur []string
	curWidth := marginWidth

	flush := func() {
		if len(cur) > 0 {
			lines = append(lines, tabBarLeftMargin+strings.Join(cur, sep))
			cur = nil
			curWidth = marginWidth
		}
	}

	for _, tab := range tabs {
		label := fmt.Sprintf(" %s %s ", tab.key, tab.name)
		var styled string
		if tab.view == m.view {
			styled = ui.ActiveTabStyle.Render(label)
		} else {
			styled = ui.InactiveTabStyle.Render(label)
		}
		labelWidth := lipgloss.Width(styled)

		addWidth := labelWidth
		if len(cur) > 0 {
			addWidth += sepWidth
		}
		if len(cur) > 0 && curWidth+addWidth > maxWidth {
			flush()
			addWidth = labelWidth
		}

		cur = append(cur, styled)
		curWidth += addWidth
	}
	flush()

	return strings.Join(lines, "\n")
}

func (m Model) renderList() string {
	if len(m.displayItems) == 0 {
		msg := "No reminders"
		switch m.view {
		case ViewToday:
			msg = "Nothing due today -- nice!"
		case ViewUpcoming:
			msg = "Nothing coming up this week"
		case ViewThisWeek:
			msg = "Nothing scheduled for this week"
		}
		if m.searchQuery != "" {
			msg = fmt.Sprintf("No results for %q", m.searchQuery)
		}
		empty := "  " + ui.CountStyle.Render(msg)
		if m.mode == ModeInsert {
			empty += "\n" + m.renderInsertBar()
		}
		return empty
	}

	// Available terminal lines for content. The tab bar may wrap onto more
	// than one line on narrow terminals, so its height is measured rather
	// than assumed. The events frame, when present, also eats into the
	// budget.
	tabBarHeight := strings.Count(m.renderTabBar(), "\n") + 1
	eventsFrameHeight := 0
	if frame := m.renderEventsFrame(); frame != "" {
		eventsFrameHeight = strings.Count(frame, "\n") + 1 // frame lines + the newline after it
	}
	formHeight := 0
	if form := m.renderForm(); form != "" {
		formHeight = strings.Count(form, "\n") + 1
	}
	barHeight := 0
	if m.mode == ModeSearch || m.mode == ModeConfirmDelete {
		barHeight = 1
	}
	maxVisible := m.height - 3 - tabBarHeight - eventsFrameHeight - formHeight - barHeight // header + blank + status
	if maxVisible < 5 {
		maxVisible = 5
	}

	now := time.Now()

	// Render each display item to its actual lines up front so the
	// scrolling window can be sized by rendered line count rather than
	// item count -- notes can wrap to several lines and group headers
	// include a blank margin line, so one item doesn't always mean one
	// terminal line.
	itemBlocks := make([][]string, len(m.displayItems))
	for i, item := range m.displayItems {
		if item.isHeader {
			style := ui.GroupHeaderStyle
			if item.overdue {
				style = ui.GroupHeaderOverdueStyle
			}
			itemBlocks[i] = strings.Split(style.Render(item.header), "\n")
			continue
		}

		lines := strings.Split(m.renderReminder(item.reminder, now, i == m.cursor), "\n")
		if m.notesShowAll || i == m.cursor {
			if notes := m.renderNotes(item.reminder); notes != "" {
				lines = append(lines, strings.Split(notes, "\n")...)
			}
		}
		itemBlocks[i] = lines
	}

	// Insert mode's quick-add bar renders as an extra line right under the
	// cursor's row, rather than pinned to the bottom of the content, so it
	// reads like opening a new line below the current one.
	if m.mode == ModeInsert && m.cursor >= 0 && m.cursor < len(itemBlocks) {
		itemBlocks[m.cursor] = append(itemBlocks[m.cursor], m.renderInsertBar())
	}

	itemLines := make([]int, len(itemBlocks))
	for i, block := range itemBlocks {
		itemLines[i] = len(block)
	}

	start := windowStart(itemLines, m.cursor, maxVisible)
	end := start
	used := 0
	for end < len(itemLines) && used+itemLines[end] <= maxVisible {
		used += itemLines[end]
		end++
	}
	if end == start && start < len(itemLines) {
		end = start + 1 // always show at least the cursor item, even if it alone overflows the budget
	}
	// Never end the visible window on a header with none of its items shown
	// below it -- that leaves an orphaned section title floating above dead
	// space. Trim it so the reclaimed room goes toward showing more of the
	// next item instead.
	for end > start+1 && end < len(itemLines) && m.displayItems[end-1].isHeader {
		end--
		used -= itemLines[end]
	}

	// If the next item doesn't fully fit in what's left of the budget, show
	// as much of it as does fit instead of leaving that room blank -- a
	// reminder clipped mid-line still reads as "there's more, scroll down"
	// rather than vanishing outright.
	var partial []string
	if remaining := maxVisible - used; remaining > 0 && end < len(itemLines) && !m.displayItems[end].isHeader {
		partial = itemBlocks[end][:remaining]
	}

	var b strings.Builder
	for i := start; i < end; i++ {
		for _, line := range itemBlocks[i] {
			b.WriteString(line)
			b.WriteString("\n")
		}
	}
	for _, line := range partial {
		b.WriteString(line)
		b.WriteString("\n")
	}

	return b.String()
}

// windowStart finds the smallest item index such that the rendered lines
// from that index through cursor (inclusive) fit within maxVisible lines,
// so the cursor's item is always visible even when items above it render
// as multiple lines.
func windowStart(itemLines []int, cursor, maxVisible int) int {
	if cursor < 0 || cursor >= len(itemLines) {
		return 0
	}
	sum := itemLines[cursor]
	start := cursor
	for start > 0 && sum+itemLines[start-1] <= maxVisible {
		start--
		sum += itemLines[start]
	}
	return start
}

// thisWeekTagRe matches the #thisweek tag on its own, for stripping it out
// of displayed notes -- it's an internal marker, not something the user
// wrote to be read.
var thisWeekTagRe = regexp.MustCompile(`(?i)#thisweek\b`)

// stripThisWeekTag removes the #thisweek tag from notes text. A line that
// contains only the tag is dropped entirely; a line with other content
// keeps that content with the tag removed and spacing normalized.
func stripThisWeekTag(notes string) string {
	lines := strings.Split(notes, "\n")
	out := lines[:0]
	for _, line := range lines {
		if !thisWeekTagRe.MatchString(line) {
			out = append(out, line)
			continue
		}
		cleaned := strings.Join(strings.Fields(thisWeekTagRe.ReplaceAllString(line, "")), " ")
		if cleaned != "" {
			out = append(out, cleaned)
		}
	}
	return strings.TrimSpace(strings.Join(out, "\n"))
}

// renderNotes renders a reminder's notes (which is also where remindctl
// stores any attached URL) wrapped to the terminal width and indented under
// the reminder's line. The #thisweek tag is stripped since it's an internal
// marker for the This Week view, not user-facing content.
func (m Model) renderNotes(r remindctl.Reminder) string {
	notes := stripThisWeekTag(strings.TrimSpace(r.Notes))
	if notes == "" {
		return ""
	}

	const indent = "      "
	width := m.width - len(indent) - 1
	if width < 20 {
		width = 20
	}

	wrapped := lipgloss.NewStyle().Width(width).Render(notes)
	lines := strings.Split(wrapped, "\n")
	for i, l := range lines {
		lines[i] = indent + ui.NotesStyle.Render(l)
	}
	return strings.Join(lines, "\n")
}

// reminderPrefixWidth is the width of the leading margin + priority dot +
// trailing space, e.g. "  ● " or, when selected, " ▸● " -- both 4 cells wide.
// Wrapped title continuation lines are indented to this width so they align
// under the first line's text.
const reminderPrefixWidth = 4

// selectionPaddingWidth reserves room for ui.SelectedStyle's horizontal
// padding, which is added when a reminder row is the cursor. Wrapping is
// budgeted for this unconditionally so wrapping stays stable as the cursor
// moves between reminders.
const selectionPaddingWidth = 2

// widthSafetyMargin absorbs terminal/font mismatches in how wide certain
// glyphs (e.g. the variation-selector symbols used in list names) render
// compared to how lipgloss measures them, so a tight wrap budget doesn't
// occasionally overflow the terminal width by a column or two.
const widthSafetyMargin = 2

func (m Model) renderReminder(r remindctl.Reminder, now time.Time, selected bool) string {
	// Priority dot
	dot := ui.PriorityIndicator(r.Priority)

	// Due date
	dueStr := ""
	if r.HasDueDate() {
		due := r.ParsedDueDate()
		dueStr = " " + ui.FormatDueDate(due, now)
	}

	// List tag
	tag := ui.ListTagStyle(r.ListName).Render(" " + r.ListName)

	// Overdue badge
	badge := ""
	if r.IsOverdue(now) {
		badge = " " + ui.OverdueBadge()
	}

	meta := dueStr + tag + badge
	metaWidth := lipgloss.Width(meta)

	titleWidth := m.width - reminderPrefixWidth - selectionPaddingWidth - widthSafetyMargin - metaWidth
	if titleWidth < 15 {
		titleWidth = 15
	}

	titleStyle := ui.TitleStyle
	if r.IsOverdue(now) {
		titleStyle = ui.TitleOverdueStyle
	}

	titleLines := strings.Split(lipgloss.NewStyle().Width(titleWidth).Render(r.Title), "\n")

	indent := strings.Repeat(" ", reminderPrefixWidth)
	cursor := lipgloss.NewStyle().Foreground(ui.ColorAccent).Bold(true).Render("▸")

	lines := make([]string, len(titleLines))
	for i, tl := range titleLines {
		styled := titleStyle.Render(tl)
		switch {
		case i > 0:
			lines[i] = indent + styled
		case selected:
			lines[i] = fmt.Sprintf(" %s%s %s", cursor, dot, styled)
		default:
			lines[i] = fmt.Sprintf("  %s %s", dot, styled)
		}
	}
	lines[len(lines)-1] += meta

	if selected {
		for i, l := range lines {
			lines[i] = ui.SelectedStyle.Render(l)
		}
	}

	return strings.Join(lines, "\n")
}

func (m Model) renderSearchBar() string {
	label := ui.InputLabelStyle.Render("  / ")
	return label + m.searchInput.View()
}

func (m Model) renderInsertBar() string {
	label := "  i "
	if m.insertList != "" {
		label = fmt.Sprintf("  i [%s] ", ui.Truncate(m.insertList, 24))
	}
	return ui.InputLabelStyle.Render(label) + m.insertInput.View()
}

func (m Model) renderAddBar() string {
	var lines []string
	if m.addStep > 0 {
		lines = append(lines, ui.FormDoneFieldStyle.Render("Title: "+m.addTitle))
	}
	if m.addStep > 1 && m.addList != "" {
		lines = append(lines, ui.FormDoneFieldStyle.Render("List: "+m.addList))
	}
	if m.addStep > 2 && m.addDue != "" {
		lines = append(lines, ui.FormDoneFieldStyle.Render("Due: "+m.addDue))
	}
	if m.addStep > 3 && m.addPriority != "" {
		lines = append(lines, ui.FormDoneFieldStyle.Render("Priority: "+m.addPriority))
	}

	if m.addStep == 4 {
		lines = append(lines, m.renderFormNotes("Notes"))
	} else {
		var label string
		switch m.addStep {
		case 0:
			label = "Title"
		case 1:
			label = "List"
		case 2:
			label = "Due"
		case 3:
			label = "Priority"
		}
		lines = append(lines, m.renderFormField(label, m.addInput))
	}

	return m.renderFormBox("Add Reminder", lines)
}

func (m Model) renderEditBar() string {
	var lines []string
	if m.editStep > 0 {
		lines = append(lines, ui.FormDoneFieldStyle.Render("Title: "+m.editTitle))
	}
	if m.editStep > 1 && m.editDue != "" {
		lines = append(lines, ui.FormDoneFieldStyle.Render("Due: "+m.editDue))
	}
	if m.editStep > 2 && m.editPriority != "" {
		lines = append(lines, ui.FormDoneFieldStyle.Render("Priority: "+m.editPriority))
	}

	if m.editStep == 3 {
		lines = append(lines, m.renderFormNotes("Notes"))
	} else {
		var label string
		switch m.editStep {
		case 0:
			label = "Title"
		case 1:
			label = "Due"
		case 2:
			label = "Priority"
		}
		lines = append(lines, m.renderFormField(label, m.editInput))
	}

	return m.renderFormBox("Edit Reminder", lines)
}

// renderFormField renders a labeled input field, wrapping the current value
// to the form box's content width instead of letting it overflow.
func (m Model) renderFormField(label string, input textinput.Model) string {
	labelLine := ui.InputLabelStyle.Render(label + ":")
	value := lipgloss.NewStyle().Width(m.formContentWidth()).Render(input.View())
	return labelLine + "\n" + value
}

// renderFormNotes renders the multi-line notes textarea. Unlike
// renderFormField, the textarea already wraps and pads its own content to
// its configured width, so its view is used as-is.
func (m Model) renderFormNotes(label string) string {
	labelLine := ui.InputLabelStyle.Render(label + ":")
	return labelLine + "\n" + m.notesArea.View()
}

// renderFormBox wraps lines in a bordered floating box.
func (m Model) renderFormBox(title string, lines []string) string {
	var body strings.Builder
	body.WriteString(ui.FormTitleStyle.Render(title))
	for _, l := range lines {
		body.WriteString("\n")
		body.WriteString(l)
	}
	return ui.FormBoxStyle.Width(m.formBoxWidth()).Render(body.String())
}

func (m Model) formBoxWidth() int {
	w := m.width - 4
	if w < 24 {
		w = 24
	}
	return w
}

func (m Model) formContentWidth() int {
	w := m.formBoxWidth() - 2 // form box horizontal padding
	if w < 20 {
		w = 20
	}
	return w
}

func (m Model) renderDeleteConfirm() string {
	return ui.ConfirmStyle.Render(fmt.Sprintf(
		"  Delete %q? (y/n)",
		ui.Truncate(m.deleteTitle, 40),
	))
}

func (m Model) renderHelp() string {
	bindings := []struct {
		key  string
		desc string
	}{
		{"j/k", "navigate up/down"},
		{"x/space", "complete reminder"},
		{"u", "undo last completion"},
		{"a", "add new reminder (step-by-step)"},
		{"i", "quick add: title @list !priority ~due #tag"},
		{"e", "edit selected reminder"},
		{"d", "delete with confirmation"},
		{"1-8", "switch view (This Week/Today/Upcoming/Lists/Teaching/Research/Habits/Tasks)"},
		{"Tab", "cycle views"},
		{"/", "search/filter"},
		{"r", "refresh data"},
		{"?", "toggle this help"},
		{"q", "quit"},
		{"Esc", "cancel current action"},
		{"shift+enter", "line break in notes field (or ctrl+j/alt+enter)"},
	}
	if m.calAvailable {
		bindings = append(bindings, struct{ key, desc string }{"c", "expand/collapse today's events"})
	}
	bindings = append(bindings, struct{ key, desc string }{"n", "toggle notes: all reminders / selected only"})

	var b strings.Builder
	b.WriteString("  ")
	b.WriteString(ui.HelpTitleStyle.Render("Keybindings"))
	b.WriteString("\n\n")

	for _, bind := range bindings {
		k := ui.HelpKeyStyle.Render("  " + bind.key)
		d := ui.HelpDescStyle.Render(bind.desc)
		b.WriteString(k + d + "\n")
	}

	return b.String()
}

// renderForm returns the add/edit form box, or "" when no form is open.
func (m Model) renderForm() string {
	switch m.mode {
	case ModeAdd, ModeAddField:
		return m.renderAddBar()
	case ModeEdit, ModeEditField:
		return m.renderEditBar()
	}
	return ""
}

func (m Model) renderStatusBar() string {
	if m.statusMsg != "" {
		if m.statusErr {
			return ui.StatusErrorStyle.Render("  " + m.statusMsg)
		}
		return ui.StatusSuccessStyle.Render("  ✓ " + m.statusMsg)
	}

	// Show keybind hints
	hints := "  j/k navigate  x complete  u undo  i quick add  a add  e edit  d delete  / search  ? help  q quit"
	if m.loading {
		hints = "  " + m.spinner.View() + " refreshing..."
	}
	return ui.StatusBarStyle.Render(hints)
}
