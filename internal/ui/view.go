package ui

import (
	"fmt"
	"github.com/charmbracelet/lipgloss"
)

var (
	// Colors
	subtle    = lipgloss.AdaptiveColor{Light: "#D9DCCF", Dark: "#626262"} // Lighter gray for visibility
	highlight = lipgloss.AdaptiveColor{Light: "#874BFD", Dark: "#7D56F4"}
	special   = lipgloss.AdaptiveColor{Light: "#43BF6D", Dark: "#73F59F"}
	accent    = lipgloss.AdaptiveColor{Light: "#00d2ff", Dark: "#00d2ff"} // Vibrant Blue
	
	// Styles
	docStyle = lipgloss.NewStyle().Margin(1, 2)

	// Panel Styles
	panelStyle = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(highlight).
		Padding(1, 1) // Removed default MarginRight(1)
	
	activePanelStyle = panelStyle.Copy().
		BorderForeground(accent)

	titleStyle = lipgloss.NewStyle().
		Foreground(accent).
		Bold(true).
		Padding(0, 1)
)

func (m MainModel) View() string {
	if m.Quitting {
		return "Bye!\n"
	}

	// Calculate widths and heights
	// Available: Width - 4 (Doc Margins)
	// Top Row: Pending(50%) + Active(50%)
	// Bottom: Events(100%)
	
	// Reduce total width slightly to prevent wrapping issues on right edge
	totalWidth := m.Width - 6 
    gap := 1
	halfWidth := (totalWidth - gap) / 2 
	
	// Heights: Header(2) + Footer(4) + DocMargin(2) = 8 reserved?
	availableHeight := m.Height - 8
	listHeight := availableHeight * 2 / 3 // Give more space to lists
	eventHeight := availableHeight - listHeight

	if listHeight < 5 {
		listHeight = 5 // Minimum height
	}

	// 1. Pending Tasks Panel (Left)
	m.pendingList.SetSize(halfWidth-2, listHeight-2) // -2 for Border+Padding (approx)
	pendingView := m.pendingList.View()
	pendingPanel := panelStyle.Copy().
		Width(halfWidth).
		Height(listHeight).
		MarginRight(gap). // Add gap
		Render(pendingView)

	// 2. Active Task Panel (Right)
	m.activeList.SetSize(halfWidth-2, listHeight-2)
	activeView := m.activeList.View()
	activePanel := activePanelStyle.Copy().
		Width(halfWidth).
		Height(listHeight).
		Render(activeView)

	// 3. Event Log Panel (Bottom)
	// Fix: Use subtle border color for Event Log
    // Width must be top row total (half + gap + half)
    eventsWidth := (halfWidth * 2) + gap
    
    // Render last few events
    var eventText string
    if len(m.events) > 0 {
        // Show last 5 events
        count := 0
        for _, e := range m.events {
            eventText += fmt.Sprintf("• %s\n", e)
            count++
            if count >= 5 {
                break
            }
        }
    } else {
        eventText = "(No recent events)"
    }
    
	eventsContent := fmt.Sprintf("Event Log...\n%s", eventText)
	eventsPanel := panelStyle.Copy().
		BorderForeground(highlight). // Change border color back to visible
		Width(eventsWidth).    
		Height(eventHeight).
		Render(eventsContent)

	// Combine Panels
	// Top Row
	topRow := lipgloss.JoinHorizontal(lipgloss.Top, pendingPanel, activePanel)
	
	// Main View (Vertical)
	mainView := lipgloss.JoinVertical(lipgloss.Left, topRow, eventsPanel)

	// Header
	header := titleStyle.Render("💠 CLAUDE ORCHESTRA | CONTROL CENTER v2.0")

	// Footer (Commands)
	// Structure:
	// (Command)
	// (input Key, select Agets, etc)
	
    var footer string
	if m.InputMode {
        // Input Mode Footer
		inputView := m.Input.View()
        helpText := "[Enter]: Confirm    [Esc]: Cancel"
        footer = fmt.Sprintf("%s\n%s", inputView, helpText)
	} else {
        // Normal Mode Footer
        // Use special color for Command Mode indicator
        cmdStatus := lipgloss.NewStyle().Foreground(special).Render("(Command Mode)")
        helpText := "[A] Add Task  [S] Start  [C] Complete  [L] Logs  [E] Edit  [R] Scan  [Q] Exit"
        footer = fmt.Sprintf("%s\n%s", cmdStatus, helpText)
	}
    
    footerView := lipgloss.NewStyle().Foreground(subtle).MarginTop(1).Render(footer)

	// Combine All
	// Use JoinVertical for header + main + footer to ensure alignment
    // Remove docStyle from JoinVertical to prevent global margin clipping header
    content := lipgloss.JoinVertical(lipgloss.Left, header, mainView, footerView)
	return docStyle.Render(content)
}
