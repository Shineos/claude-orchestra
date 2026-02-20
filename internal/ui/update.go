package ui

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"shineos/claude-orchestra/internal/orchestrator"
)

type editFinishedMsg struct {
	err  error
	path string
	id   int
}

// isSignalError checks if the error is due to a signal (e.g., Ctrl+C)
func isSignalError(err error) bool {
	if err == nil {
		return false
	}
	if exitErr, ok := err.(*exec.ExitError); ok {
		exitCode := exitErr.ExitCode()
		return exitCode >= 128 && exitCode <= 143
	}
	return false
}



func (m MainModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var (
		cmd  tea.Cmd
		cmds []tea.Cmd
	)

	switch msg := msg.(type) {
	case editFinishedMsg:
		// Check if error is a signal (user cancelled with Ctrl+C)
		if msg.err != nil {
			// Clean up temp file on error
			if msg.path != "" {
				os.Remove(msg.path)
			}
			// Don't show error for signal interruptions (user cancelled)
			if !isSignalError(msg.err) {
				m.events = append([]string{fmt.Sprintf("[ERROR] Edit failed: %v", msg.err)}, m.events...)
			}
			return m, nil
		}
		content, err := os.ReadFile(msg.path)
		if err != nil {
			m.events = append([]string{fmt.Sprintf("[ERROR] Failed to read edited file: %v", err)}, m.events...)
			return m, nil
		}
		os.Remove(msg.path)
		// Trim newline if editor added one, but description might need it?
		// Usually descriptions are single line or short text.
		// Let's trim space around.
		// But import "strings" is needed.
		// For now, raw string is fine, json handles it.
		// Actually, let's just use string(content).
		newDesc := string(content)
		if len(newDesc) > 0 && newDesc[len(newDesc)-1] == '\n' {
			newDesc = newDesc[:len(newDesc)-1]
		}

		m.events = append([]string{fmt.Sprintf("Edited task #%d", msg.id)}, m.events...)
		return m, orchestrator.EditTaskCmd(msg.id, newDesc)

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

        // Should we skip custom keys if filtering?
        isFiltering := m.pendingList.FilterState() == list.Filtering || m.activeList.FilterState() == list.Filtering
        
        if isFiltering {
            // Allow Enter to verify/select in filter mode (handled by list usually, but let's be safe)
            // Actually, list handles Enter to stop filtering.
            // We just want to skip "s", "a", etc.
            // But we process InputMode first.
        }


        // Logic depends on InputMode
        if m.InputMode {
            // Special handling for AddingTask wizard
            if m.AddingTask {
                switch m.AddingStep {
                case 1: // Description
                    if msg.Type == tea.KeyEnter {
                        desc := strings.TrimSpace(m.Input.Value())
                        if desc != "" {
                            m.PendingTaskDesc = desc
                            m.AddingStep = 2
                            m.Input.Blur() // We use keys for selection now
                            return m, nil
                        }
                    }
                case 2: // Agent Selection
                    switch msg.Type {
                    case tea.KeyEnter:
                        m.PendingTaskAgent = m.AgentChoices[m.AgentChoiceIndex]
                        if m.PendingTaskAgent == "AI (auto)" {
                            m.PendingTaskAgent = "" // Empty means auto
                        }
                        m.AddingStep = 3
                        return m, nil
                    case tea.KeyTab, tea.KeyRight, tea.KeyDown:
                        m.AgentChoiceIndex = (m.AgentChoiceIndex + 1) % len(m.AgentChoices)
                        return m, nil
                    case tea.KeyShiftTab, tea.KeyLeft, tea.KeyUp:
                        m.AgentChoiceIndex = (m.AgentChoiceIndex - 1 + len(m.AgentChoices)) % len(m.AgentChoices)
                        return m, nil
                    }
                case 3: // Confirmation
                    if msg.Type == tea.KeyEnter {
                        m.events = append([]string{fmt.Sprintf("Adding task: %s...", m.PendingTaskDesc)}, m.events...)
                        cmd = orchestrator.AddTaskCmd(m.PendingTaskDesc, m.PendingTaskAgent)
                        m.AddingTask = false
                        m.AddingStep = 0
                        m.InputMode = false
                        m.Input.Blur()
                        return m, cmd
                    }
                    if msg.String() == "e" || msg.String() == "E" {
                        m.AddingStep = 1
                        m.Input.Focus()
                        m.Input.SetValue(m.PendingTaskDesc)
                        return m, nil
                    }
                }

                if msg.Type == tea.KeyEsc {
                    m.AddingTask = false
                    m.AddingStep = 0
                    m.InputMode = false
                    m.Input.Blur()
                    return m, nil
                }

                if m.AddingStep == 1 {
                    m.Input, cmd = m.Input.Update(msg)
                    return m, cmd
                }
                return m, nil
            }

            switch msg.Type {
            case tea.KeyEnter:
                if m.Input.Value() != "" {
                    if m.ActiveCommand != "" {
                        // Parse ID
                        var id int
                        if _, err := fmt.Sscanf(m.Input.Value(), "%d", &id); err == nil && id > 0 {
                            switch m.ActiveCommand {
                            case "start":
                                m.events = append([]string{fmt.Sprintf("Starting task #%d...", id)}, m.events...)
                                cmd = orchestrator.StartTaskCmd(id)
                            case "complete":
                                m.events = append([]string{fmt.Sprintf("Completing task #%d...", id)}, m.events...)
                                cmd = orchestrator.CompleteTaskCmd(id)
                            case "logs":
                                cmd = orchestrator.LogsTuiCmd(id)
                            case "verbose":
                                cmd = orchestrator.OpenRawLogCmd(id)
                            case "edit":
                                desc := ""
                                for _, t := range m.Tasks {
                                    if t.ID == id {
                                        desc = t.Description
                                        break
                                    }
                                }
                                cmd = openEditor(id, desc)
                            case "open":
                                m.events = append([]string{fmt.Sprintf("Opening task #%d...", id)}, m.events...)
                                cmd = orchestrator.OpenTaskCmd(id)
                            case "watch":
                                agent := ""
                                for _, t := range m.Tasks {
                                    if t.ID == id {
                                        agent = t.Agent
                                        break
                                    }
                                }
                                if agent != "" {
                                    m.events = append([]string{fmt.Sprintf("Launching agent %s in background...", agent)}, m.events...)
                                    cmd = orchestrator.SpawnAgentCmd(agent)
                                } else {
                                    m.events = append([]string{"[ERROR] No agent assigned to this task"}, m.events...)
                                }
                            }
                            cmds = append(cmds, cmd)
                        } else {
                            m.events = append([]string{"[ERROR] Invalid ID format"}, m.events...)
                        }
                        m.ActiveCommand = ""
                    }
                }
                m.Input.SetValue("")
                m.InputMode = false
                m.Input.Blur()
                m.ActiveCommand = ""
                return m, tea.Batch(cmds...)
            case tea.KeyEsc:
                m.InputMode = false
                m.Input.Blur()
                m.ActiveCommand = ""
                return m, nil
            default:
                m.Input, cmd = m.Input.Update(msg)
                cmds = append(cmds, cmd)
                return m, cmd
            }
        } else if isFiltering {
            // Skip custom shortcuts
        } else {
            switch msg.String() {
            case "ctrl+c":
                m.Quitting = true
                return m, tea.Quit
            case "a", "A":
                m.AddingTask = true
                m.AddingStep = 1
                m.InputMode = true
                m.ActiveCommand = "" // Reset
                m.Input.Placeholder = "Task description..."
                m.Input.SetValue("")
                m.Input.Focus()
                return m, textinput.Blink
            case "s", "S":
                if m.Tab == 0 || m.Tab == 1 || m.Tab == 2 {
                    id := m.getSelectedID()
                    m.InputMode = true
                    m.ActiveCommand = "start"
                    m.Input.Placeholder = "Task ID"
                    if id > 0 {
                        m.Input.SetValue(fmt.Sprintf("%d", id))
                    } else {
                        m.Input.SetValue("")
                    }
                    m.Input.Focus()
                    return m, textinput.Blink
                }
            case "c", "C":
                if m.Tab == 0 || m.Tab == 1 {
                    id := m.getSelectedID()
                    m.InputMode = true
                    m.ActiveCommand = "complete"
                    m.Input.Placeholder = "Task ID"
                    if id > 0 {
                        m.Input.SetValue(fmt.Sprintf("%d", id))
                    } else {
                        m.Input.SetValue("")
                    }
                    m.Input.Focus()
                    return m, textinput.Blink
                }
            case "e", "E":
                if m.Tab == 0 || m.Tab == 1 || m.Tab == 2 {
                    id := m.getSelectedID()
                    m.InputMode = true
                    m.ActiveCommand = "edit"
                    m.Input.Placeholder = "Task ID"
                    if id > 0 {
                        m.Input.SetValue(fmt.Sprintf("%d", id))
                    } else {
                        m.Input.SetValue("")
                    }
                    m.Input.Focus()
                    return m, textinput.Blink
                }
            case "r", "R":
                m.events = append([]string{"Refreshing tasks..."}, m.events...)
                cmds = append(cmds, orchestrator.FetchTasksCmd())
            case "x", "X", "t", "T", "k", "K":
                // Stop/Terminate task
                if m.Tab == 0 || m.Tab == 1 {
                     var id int
                     if m.Tab == 0 && len(m.pendingList.Items()) > 0 {
                         if i, ok := m.pendingList.SelectedItem().(item); ok { id = i.id }
                     } else if m.Tab == 1 && len(m.activeList.Items()) > 0 {
                         if i, ok := m.activeList.SelectedItem().(item); ok { id = i.id }
                     }
                     // Keep x as immediate if no ambiguity? Or make consistent?
                     // User didn't ask for x to be ID-based specifically (S, C, L, E were asked).
                     // But consistency is good.
                     // The requirement was: [S] Start [C] Complete [L] Logs [E] Edit.
                     // I will leave 'x' as is for now unless requested, or maybe implicit?
                     // Let's stick to requested ones to avoid annoyance if they want quick stop.
                     if id > 0 {
                        m.events = append([]string{fmt.Sprintf("Stopping task #%d...", id)}, m.events...)
                        cmd = orchestrator.StopTaskCmd(id)
                        cmds = append(cmds, cmd)
                     }
                }
            case "d", "backspace":
                var list *list.Model
                if m.Tab == 0 {
                    list = &m.pendingList
                } else if m.Tab == 1 {
                    list = &m.activeList
                } else if m.Tab == 2 {
                    list = &m.completeList
                }
                
                if list != nil && len(list.Items()) > 0 {
                    selectedItem := list.SelectedItem()
                    if selectedItem != nil {
                        id := selectedItem.(item).id
                        if id > 0 {
                            m.events = append([]string{fmt.Sprintf("Removing task #%d...", id)}, m.events...)
                            cmd = orchestrator.RemoveTaskCmd(id)
                            cmds = append(cmds, cmd)
                        }
                    }
                }
            case "l", "L":
                 id := m.getSelectedID()
                 m.InputMode = true
                 m.ActiveCommand = "logs"
                 m.Input.Placeholder = "Task ID (0 for all)"
                 if id > 0 {
                     m.Input.SetValue(fmt.Sprintf("%d", id))
                 } else {
                     m.Input.SetValue("0")
                 }
                 m.Input.Focus()
                 return m, textinput.Blink

             case "v", "V":
                 id := m.getSelectedID()
                 m.InputMode = true
                 m.ActiveCommand = "verbose"
                 m.Input.Placeholder = "Task ID for detailed logs"
                 if id > 0 {
                     m.Input.SetValue(fmt.Sprintf("%d", id))
                 } else {
                     m.Input.SetValue("")
                 }
                 m.Input.Focus()
                 return m, textinput.Blink
             case "o", "O":
                 if m.Tab == 0 || m.Tab == 1 || m.Tab == 2 {
                     id := m.getSelectedID()
                     m.InputMode = true
                     m.ActiveCommand = "open"
                     m.Input.Placeholder = "Task ID"
                     if id > 0 {
                         m.Input.SetValue(fmt.Sprintf("%d", id))
                     } else {
                         m.Input.SetValue("")
                     }
                     m.Input.Focus()
                     return m, textinput.Blink
                 }

             case "w", "W":
                 id := m.getSelectedID()
                 m.InputMode = true
                 m.ActiveCommand = "watch"
                 m.Input.Placeholder = "Task ID to launch agent"
                 if id > 0 {
                     m.Input.SetValue(fmt.Sprintf("%d", id))
                 } else {
                     m.Input.SetValue("")
                 }
                 m.Input.Focus()
                 return m, textinput.Blink

            case "tab":
                m.Tab = (m.Tab + 1) % 3
            case "left":
                m.Tab = (m.Tab - 1 + 3) % 3
            case "right":
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
		// Compute hash to detect changes
		newHash := computeTasksHash(msg)
		hasChanges := newHash != m.tasksHash

		// Always update tasks data
		m.Tasks = msg
		m.tasksHash = newHash

		// Only update UI if there are actual changes
		if hasChanges || !m.Loaded {
			// Show pending and recently completed tasks in pending list
			m.pendingList.SetItems(tasksToItems(msg, "pending"))
			// Show in_progress, failed, stopped
			m.activeList.SetItems(tasksToItems(msg, "in_progress", "failed", "stopped"))
			// Show completed
			m.completeList.SetItems(tasksToItems(msg, "completed"))
			m.Loaded = true
		}
		m.Spinner, _ = m.Spinner.Update(spinner.TickMsg{})
		// Schedule next auto-refresh
		if m.AutoRefresh {
			cmds = append(cmds, tea.Tick(autoRefreshInterval, func(t time.Time) tea.Msg {
				return tickMsg{isAuto: true}
			}))
		}

	case tickMsg:
		// Auto-refresh triggered (silent)
		if m.AutoRefresh {
			// Fetch tasks silently without triggering full redraw message
			cmds = append(cmds, func() tea.Msg {
				return silentRefreshMsg{}
			})
		}

	case silentRefreshMsg:
		// Perform silent fetch - no event message, no flicker
		cmds = append(cmds, orchestrator.FetchTasksCmd())
		// Don't add "Tasks refreshed" message for auto-refresh

	case orchestrator.ErrorMsg:
		m.Err = msg
		m.events = append([]string{fmt.Sprintf("Error: %v", msg)}, m.events...)
		// 既に実行中などのエラーが出た際、画面が古い状態（Pending のまま）である可能性が高いため
		// 明示的にリフレッシュを発行して同期を促す
		return m, func() tea.Msg { return orchestrator.FetchTasksCmd()() }
	}

	// Handle global updates
    var cmdList tea.Cmd
    
    // Only pass key messages to the active list to prevent simultaneous scrolling
    _, isKey := msg.(tea.KeyMsg)
    _, isMouse := msg.(tea.MouseMsg) // Mouse events also need to be routed or handled by both? List handles scroll wheel.

    if isKey || isMouse {
        if m.Tab == 0 {
            m.pendingList, cmdList = m.pendingList.Update(msg)
            cmds = append(cmds, cmdList)
        } else if m.Tab == 1 {
            m.activeList, cmdList = m.activeList.Update(msg)
            cmds = append(cmds, cmdList)
        } else {
            m.completeList, cmdList = m.completeList.Update(msg)
            cmds = append(cmds, cmdList)
        }
    } else {
        // Pass other messages (tick, resize, etc) to both
        m.pendingList, cmdList = m.pendingList.Update(msg)
        cmds = append(cmds, cmdList)
    
        m.activeList, cmdList = m.activeList.Update(msg)
        cmds = append(cmds, cmdList)

        m.completeList, cmdList = m.completeList.Update(msg)
        cmds = append(cmds, cmdList)
    }

	return m, tea.Batch(cmds...)
}

func (m MainModel) getSelectedID() int {
    activeList := &m.pendingList
    if m.Tab == 1 {
        activeList = &m.activeList
    } else if m.Tab == 2 {
        activeList = &m.completeList
    }
    
    if len(activeList.Items()) > 0 {
        if i, ok := activeList.SelectedItem().(item); ok {
            return i.id
        }
    }
    
    // Check all lists? Or just fail?
    // User expects to operate on selected item.
    return 0
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
			} else if t.Status == "stopped" {
				prefix = "[STOPPED] "
			} else if t.Status == "in_progress" {
				prefix = "[RUNNING] "
			}

            // Determine Agent Color
            // Define colors
            var color lipgloss.Color
            switch strings.ToLower(t.Agent) {
            case "tests", "tester":
                color = lipgloss.Color("197") // Red-ish
            case "frontend", "ui":
                color = lipgloss.Color("39") // Blue
            case "backend", "api":
                color = lipgloss.Color("208") // Orange
            case "docs":
                color = lipgloss.Color("220") // Yellow
            default:
                color = lipgloss.Color("240") // Grey/Default
            }
            
            agentTag := lipgloss.NewStyle().
                Background(color).
                Foreground(lipgloss.Color("255")).
                Bold(true).
                Padding(0, 1).
                Render(t.Agent)

            if t.Agent == "" {
                agentTag = lipgloss.NewStyle().
                Background(lipgloss.Color("237")).
                Foreground(lipgloss.Color("245")).
                Padding(0, 1).
                Render("Unassigned")
            }

			// Handle empty descriptions
			desc := t.Description
			if desc == "" {
				desc = "(No description)"
			}

			items = append(items, item{
				id:    t.ID,
				title: fmt.Sprintf("%s %s#%d", agentTag, prefix, t.ID),
				desc:  desc,
			})
		}
	}
	return items
}

func openEditor(id int, desc string) tea.Cmd {
	file, err := os.CreateTemp("", "claude-task-*.txt")
	if err != nil {
		return func() tea.Msg { return editFinishedMsg{err: fmt.Errorf("CreateTemp: %w", err), id: id} }
	}

	if _, err := file.WriteString(desc); err != nil {
		file.Close()
		os.Remove(file.Name())
		return func() tea.Msg { return editFinishedMsg{err: fmt.Errorf("WriteString: %w", err), id: id} }
	}
	file.Close()

	// Store temp file path for cleanup
	tempFilePath := file.Name()

	editor := os.Getenv("EDITOR")
	if editor == "" {
		editor = "vim"
		if _, err := exec.LookPath("vim"); err != nil {
			editor = "nano"
		}
	}

	c := exec.Command(editor, tempFilePath)
	// Ensure the process has proper cleanup
	return tea.ExecProcess(c, func(err error) tea.Msg {
		// Always try to clean up the temp file
		// If edit was successful (err == nil), we'll read it first in the Update handler
		// If edit failed, we still clean up
		if err != nil {
			os.Remove(tempFilePath)
			return editFinishedMsg{err: err, path: tempFilePath, id: id}
		}
		// On success, return the path so the Update handler can read and then clean up
		return editFinishedMsg{err: nil, path: tempFilePath, id: id}
	})
}
