package ui

import (
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"shineos/claude-orchestra/internal/orchestrator"
	"fmt"
	"github.com/charmbracelet/bubbles/list"
)

func (m MainModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var (
		cmd  tea.Cmd
		cmds []tea.Cmd
	)

	switch msg := msg.(type) {
	case tea.KeyMsg:
        // Global keys (handled regardless of mode, but after input check)
        if msg.Type == tea.KeyEsc {
            if m.InputMode {
                m.InputMode = false
                m.Input.Blur()
                return m, nil
            }
            if m.pendingList.FilterState() == list.Filtering || m.activeList.FilterState() == list.Filtering {
                break
            }
            return m, nil // Consume ESC to prevent exit
        }
        if msg.String() == "q" && !m.InputMode {
            m.Quitting = true
            return m, tea.Quit
        }

		// Logic depends on InputMode
		if m.InputMode {
			switch msg.Type {
			case tea.KeyEnter:
				if m.Input.Value() != "" {
                    m.events = append([]string{fmt.Sprintf("Adding task: %s...", m.Input.Value())}, m.events...)
					cmd = orchestrator.AddTaskCmd(m.Input.Value())
					cmds = append(cmds, cmd)
				}
				m.Input.SetValue("")
				m.InputMode = false
				m.Input.Blur()
                return m, tea.Batch(cmds...)
			default:
				m.Input, cmd = m.Input.Update(msg)
				cmds = append(cmds, cmd)
                return m, cmd
			}
		} else {
			switch msg.String() {
			case "ctrl+c":
				m.Quitting = true
				return m, tea.Quit
			case "a":
				m.InputMode = true
				m.Input.Focus()
				return m, textinput.Blink
			case "s":
				if m.Tab == 0 && len(m.pendingList.Items()) > 0 {
					selectedItem := m.pendingList.SelectedItem()
					if selectedItem != nil {
						var id int
						fmt.Sscanf(selectedItem.(item).title, "#%d", &id)
						if id > 0 {
                            m.events = append([]string{fmt.Sprintf("Starting task #%d...", id)}, m.events...)
							cmd = orchestrator.StartTaskCmd(id)
							cmds = append(cmds, cmd)
						}
					}
				}
			case "c":
				if m.Tab == 1 && len(m.activeList.Items()) > 0 {
					selectedItem := m.activeList.SelectedItem()
					if selectedItem != nil {
						var id int
						fmt.Sscanf(selectedItem.(item).title, "#%d", &id)
						if id > 0 {
                            m.events = append([]string{fmt.Sprintf("Completing task #%d...", id)}, m.events...)
							cmd = orchestrator.CompleteTaskCmd(id)
							cmds = append(cmds, cmd)
						}
					}
				}
            case "e":
                m.events = append([]string{"[Edit] Not implemented yet."}, m.events...)
            case "r":
                m.events = append([]string{"Scanning tasks..."}, m.events...)
                cmds = append(cmds, orchestrator.FetchTasksCmd())
			case "x":
				if m.Tab == 1 && len(m.activeList.Items()) > 0 {
					selectedItem := m.activeList.SelectedItem()
					if selectedItem != nil {
						var id int
						fmt.Sscanf(selectedItem.(item).title, "#%d", &id)
						if id > 0 {
                            m.events = append([]string{fmt.Sprintf("Stopping task #%d...", id)}, m.events...)
							cmd = orchestrator.StopTaskCmd(id)
							cmds = append(cmds, cmd)
						}
					}
				}
			case "d", "backspace":
				var list *list.Model
				if m.Tab == 0 {
					list = &m.pendingList
				} else if m.Tab == 1 {
					list = &m.activeList
				}
				
				if list != nil && len(list.Items()) > 0 {
					selectedItem := list.SelectedItem()
					if selectedItem != nil {
						var id int
						fmt.Sscanf(selectedItem.(item).title, "#%d", &id)
						if id > 0 {
                            m.events = append([]string{fmt.Sprintf("Removing task #%d...", id)}, m.events...)
							cmd = orchestrator.RemoveTaskCmd(id)
							cmds = append(cmds, cmd)
						}
					}
				}
			case "l":
				return m, orchestrator.LogsTuiCmd()
			case "tab":
				m.Tab = (m.Tab + 1) % 3
			}
		}

	case tea.WindowSizeMsg:
		m.Width = msg.Width
		m.Height = msg.Height
	
	case spinner.TickMsg:
		m.Spinner, cmd = m.Spinner.Update(msg)
		cmds = append(cmds, cmd)

	case orchestrator.TaskLoadMsg:
		m.pendingList.SetItems(tasksToItems(msg, "pending"))
        // Show both in_progress and failed in the active list for visibility
		m.activeList.SetItems(tasksToItems(msg, "in_progress", "failed"))
		m.Loaded = true
        m.events = append([]string{"Tasks refreshed."}, m.events...)
		m.Spinner, _ = m.Spinner.Update(spinner.TickMsg{})
	
	case orchestrator.ErrorMsg:
		m.Err = msg
        m.events = append([]string{fmt.Sprintf("Error: %v", msg)}, m.events...)
	}

	// Update components based on focus (Tab)
	m.pendingList, cmd = m.pendingList.Update(msg)
	cmds = append(cmds, cmd)

	m.activeList, cmd = m.activeList.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

func tasksToItems(tasks []orchestrator.Task, statuses ...string) []list.Item {
	var items []list.Item
	for _, t := range tasks {
        match := false
        for _, s := range statuses {
            if t.Status == s {
                match = true
                break
            }
        }
		if match {
            prefix := ""
            if t.Status == "failed" {
                prefix = "[FAILED] "
            }
			items = append(items, item{
				title: fmt.Sprintf("%s#%d %s", prefix, t.ID, t.Agent),
				desc:  t.Description,
			})
		}
	}
	return items
}
