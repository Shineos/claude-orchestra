package ui

import (
	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"shineos/claude-orchestra/internal/orchestrator"
)

// MainModel is the main state of the application
type MainModel struct {
	// State
	Tab          int // 0: Pending, 1: Active, 2: Events
	InputMode    bool
	Quitting     bool
	Loaded       bool
	Width        int
	Height       int
	Err          error

	// Data
	Tasks        []orchestrator.Task
    events       []string // Event log history
	
	// Components
	pendingList  list.Model
	activeList   list.Model
	Spinner      spinner.Model
	Input        textinput.Model
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
		item{title: "Fix TUI Layout", desc: "Resolve ncurses resizing issues"},
		item{title: "Add Auth Logic", desc: "Integrate Supabase Auth"},
	}
	pList := list.New(pItems, list.NewDefaultDelegate(), 0, 0)
	pList.Title = "Pending Tasks"
	pList.SetShowHelp(false)

	aItems := []list.Item{
		item{title: "Refactor API", desc: "Optimize RPC calls"},
	}
	aList := list.New(aItems, list.NewDefaultDelegate(), 0, 0)
	aList.Title = "Active / Recent"
	aList.SetShowHelp(false)

	return MainModel{
		Tab:         0,
		Spinner:     s,
		Input:       ti,
		pendingList: pList,
		activeList:  aList,
	}
}

func (m MainModel) Init() tea.Cmd {
	return tea.Batch(m.Spinner.Tick, orchestrator.FetchTasksCmd())
}
