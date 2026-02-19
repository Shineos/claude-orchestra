package ui

import (
	"time"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"shineos/claude-orchestra/internal/orchestrator"
)

// MainModel is the main state of the application
type MainModel struct {
	// State
	Tab          int // 0: Pending, 1: Active, 2: Complete
	InputMode    bool
	Quitting     bool
	Loaded       bool
	Width        int
	Height       int
	Err          error
    SessionStartTime time.Time // To filter old completed tasks

	// Data
	Tasks        []orchestrator.Task
    events       []string // Event log history
    ActiveCommand string   // Current command waiting for ID input (start, complete, logs, edit)
    ActiveTaskID  int      // ID being input/confirmed

	// Process tracking - for cleanup
	editorTempFile string // Track temp file for cleanup

	// Components
	pendingList  list.Model
	activeList   list.Model
	completeList list.Model
	Spinner      spinner.Model
	Input        textinput.Model

	// Wizard State for Add Task
	AddingTask       bool
	AddingStep       int // 1: Desc, 2: Agent, 3: Confirm
	PendingTaskDesc  string
	PendingTaskAgent string
	AgentChoiceIndex int
	AgentChoices     []string
}

// InitialModel returns the initial state of the application
func InitialModel() MainModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	
	ti := textinput.New()
	ti.Placeholder = "Task description..."
	ti.CharLimit = 156
	ti.Width = 50

	// Initialize Lists
	pItems := []list.Item{
		item{title: "Loading...", desc: "Fetching tasks from orchestrator"},
	}
	pList := list.New(pItems, list.NewDefaultDelegate(), 0, 0)
	pList.Title = "Pending Tasks"
	pList.SetShowHelp(false)

	aItems := []list.Item{}
	aList := list.New(aItems, list.NewDefaultDelegate(), 0, 0)
	aList.Title = "Active Tasks"
	aList.SetShowHelp(false)

	cItems := []list.Item{}
	cList := list.New(cItems, list.NewDefaultDelegate(), 0, 0)
	cList.Title = "Completed"
	cList.SetShowHelp(false)

	return MainModel{
		Tab:              0,
		Spinner:          s,
		Input:            ti,
		pendingList:      pList,
		activeList:       aList,
		completeList:     cList,
		SessionStartTime: time.Now(),
		AgentChoices: []string{
			"AI (auto)",
			"frontend",
			"backend",
			"tests",
			"docs",
			"planner",
			"architect",
			"reviewer",
			"tester",
		},
	}
}

func (m MainModel) Init() tea.Cmd {
	return tea.Batch(m.Spinner.Tick, orchestrator.FetchTasksCmd())
}
