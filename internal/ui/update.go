package ui

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"shineos/claude-orchestra/internal/orchestrator"
)

type editFinishedMsg struct {
	err  error
	path string
	id   int
}



func (m MainModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var (
		cmd  tea.Cmd
		cmds []tea.Cmd
	)

	switch msg := msg.(type) {
	case editFinishedMsg:
		if msg.err != nil {
			m.events = append([]string{fmt.Sprintf("[ERROR] Edit failed: %v", msg.err)}, m.events...)
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
            switch msg.Type {
            case tea.KeyEnter:
                if m.Input.Value() != "" {
                    if m.ActiveCommand != "" {
                        // Parse ID
                       						// Parse ID
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
                            case "edit":
                                // We need description for edit, but finding usage...
                                // Wait, openEditor needs description to prefill.
                                // If we type ID manually, we need to fetch task first?
                                // Simplified: For edit, just finding item in list is best.
                                // But if user wants to edit arbitrary ID?
                                // We'd need to async fetch task, but that complicates TUI.
                                // Let's fallback to current list lookup if ID matches, else error or empty.
                                // actually for Edit, "Edit Task #ID" -> we need new text.
                                // The openEditor takes (id, desc).
                                // If we don't have desc, we can pass empty? Or read from file in openEditor?
								desc := ""
								for _, t := range m.Tasks {
									if t.ID == id {
										desc = t.Description
										break
									}
								}
								cmd = openEditor(id, desc)
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
					} else {
						// Default Add Task
						desc := m.Input.Value()
						agent := ""

						// Validate task description is not empty
						desc = strings.TrimSpace(desc)
						if desc == "" {
							m.events = append([]string{"[ERROR] Task description cannot be empty"}, m.events...)
							m.Input.SetValue("")
							m.InputMode = false
							m.Input.Blur()
							m.ActiveCommand = ""
							return m, nil
						}

						// Check for @agent syntax
						if strings.HasPrefix(desc, "@") {
							parts := strings.SplitN(desc, " ", 2)
							if len(parts) > 1 {
								candidate := strings.TrimPrefix(parts[0], "@")
								// Basic validation for known agents
								knownAgents := []string{"frontend", "backend", "tests", "docs", "planner", "architect", "reviewer", "tester"}
								for _, a := range knownAgents {
									if candidate == a {
										agent = candidate
										desc = strings.TrimSpace(parts[1])
										break
									}
								}
							}
						}

						// Validate again after @agent extraction
						desc = strings.TrimSpace(desc)
						if desc == "" {
							m.events = append([]string{"[ERROR] Task description cannot be empty after @agent"}, m.events...)
							m.Input.SetValue("")
							m.InputMode = false
							m.Input.Blur()
							m.ActiveCommand = ""
							return m, nil
						}

						// Simple auto-inference if no agent specified
						if agent == "" {
							descLower := strings.ToLower(desc)
							if strings.Contains(descLower, "test") || strings.Contains(descLower, "spec") {
								agent = "tests"
							} else if strings.Contains(descLower, "ui") || strings.Contains(descLower, "css") || strings.Contains(descLower, "html") || strings.Contains(descLower, "frontend") {
								agent = "frontend"
							} else if strings.Contains(descLower, "api") || strings.Contains(descLower, "database") || strings.Contains(descLower, "backend") {
								agent = "backend"
							} else if strings.Contains(descLower, "doc") || strings.Contains(descLower, "README") {
								agent = "docs"
							}
						}

						if agent != "" {
							m.events = append([]string{fmt.Sprintf("Adding task for %s: %s...", agent, desc)}, m.events...)
						} else {
							m.events = append([]string{fmt.Sprintf("Adding task: %s...", desc)}, m.events...)
						}
						cmd = orchestrator.AddTaskCmd(desc, agent)
						cmds = append(cmds, cmd)
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
                m.InputMode = true
                m.ActiveCommand = "" // Reset
                m.Input.Placeholder = "Task description..."
                m.Input.Focus()
                return m, textinput.Blink
            case "s", "S":
                if m.Tab == 0 || m.Tab == 1 {
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
                if m.Tab == 0 || m.Tab == 1 {
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
                m.events = append([]string{"Scanning tasks..."}, m.events...)
                cmds = append(cmds, orchestrator.FetchTasksCmd())
            case "x":
                // x is stop (similar logic to others)
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
                m.Tab = (m.Tab + 1) % 2
            case "left":
                m.Tab = 0
            case "right":
                m.Tab = 1
            }
        }

	case tea.WindowSizeMsg:
		m.Width = msg.Width
		m.Height = msg.Height

	case spinner.TickMsg:
		m.Spinner, cmd = m.Spinner.Update(msg)
		cmds = append(cmds, cmd)

	case orchestrator.TaskLoadMsg:
		// Show pending and recently completed tasks in pending list
		m.pendingList.SetItems(tasksToItems(msg, "pending"))
		// Show in_progress, failed, and stopped in active list
		m.activeList.SetItems(tasksToItems(msg, "in_progress", "failed", "stopped"))
		m.Loaded = true
		m.events = append([]string{"Tasks refreshed."}, m.events...)
		m.Spinner, _ = m.Spinner.Update(spinner.TickMsg{})

	case orchestrator.ErrorMsg:
		m.Err = msg
		m.events = append([]string{fmt.Sprintf("Error: %v", msg)}, m.events...)
	}

	// Handle global updates
	m.pendingList, cmd = m.pendingList.Update(msg)
	cmds = append(cmds, cmd)

	m.activeList, cmd = m.activeList.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

func (m MainModel) getSelectedID() int {
    activeList := &m.pendingList
    if m.Tab == 1 {
        activeList = &m.activeList
    }
    
    if len(activeList.Items()) > 0 {
        if i, ok := activeList.SelectedItem().(item); ok {
            return i.id
        }
    }
    
    // Fallback to the other list if current is empty or nothing selected
    otherList := &m.activeList
    if m.Tab == 1 {
        otherList = &m.pendingList
    }
    if len(otherList.Items()) > 0 {
        if i, ok := otherList.SelectedItem().(item); ok {
            return i.id
        }
    }
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
			}

			// Determine model badge
			var badge string
			switch t.Agent {
			case "planner", "architect", "orchestrator", "root-cause-verifier":
				badge = "[Opus]"
			case "tests", "tester", "reviewer":
				badge = "[Haiku]"
			default:
				// frontend, backend, docs, etc.
				badge = "[Sonnet]"
			}

			// Handle empty descriptions
			desc := t.Description
			if desc == "" {
				desc = "(No description)"
			}

			items = append(items, item{
				id:    t.ID,
				title: fmt.Sprintf("%s%s #%d %s", badge, prefix, t.ID, t.Agent),
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
