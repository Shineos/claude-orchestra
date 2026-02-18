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
	// Columns: Pending, Active, Complete (3 cols)
	
	totalWidth := m.Width - 6 
    gap := 1
    // 3 columns, 2 gaps
	colWidth := (totalWidth - (gap * 2)) / 3
	
	// Heights: Header(2) + Footer(4) + DocMargin(2) = 8 reserved
    const fixedEventHeight = 8 
	availableHeight := m.Height - 8
	listHeight := availableHeight - fixedEventHeight

	if listHeight < 5 {
		listHeight = 5 // Minimum height
	}

	// 1. Pending Tasks Panel (Left)
    pStyle := panelStyle
    if m.Tab == 0 {
        pStyle = activePanelStyle
    }
	m.pendingList.SetSize(colWidth-2, listHeight-2)
	pendingView := m.pendingList.View()
	pendingPanel := pStyle.Copy().
		Width(colWidth).
		Height(listHeight).
		MarginRight(gap).
		Render(pendingView)

	// 2. Active Task Panel (Middle)
    aStyle := panelStyle
    if m.Tab == 1 {
        aStyle = activePanelStyle
    }
	m.activeList.SetSize(colWidth-2, listHeight-2)
	activeView := m.activeList.View()
	activePanel := aStyle.Copy().
		Width(colWidth).
		Height(listHeight).
		MarginRight(gap).
		Render(activeView)

    // 3. Complete Task Panel (Right)
    cStyle := panelStyle
    if m.Tab == 2 {
        cStyle = activePanelStyle
    }
    m.completeList.SetSize(colWidth-2, listHeight-2)
    completeView := m.completeList.View()
    completePanel := cStyle.Copy().
        Width(colWidth).
        Height(listHeight).
        Render(completeView)

	// 3. Event Log Panel (Bottom)
    eventsWidth := (colWidth * 3) + (gap * 2)
    
    // Render last few events
    var eventText string
    maxEvents := 5
    for i := 0; i < maxEvents; i++ {
        if i < len(m.events) {
            eventText += fmt.Sprintf("• %s\n", m.events[i])
        } else {
            eventText += "\n" 
        }
    }
    
	eventsContent := fmt.Sprintf("Event Log...\n%s", eventText)
	eventsPanel := panelStyle.Copy().
		BorderForeground(highlight).
		Width(eventsWidth).    
		Height(fixedEventHeight).
		Render(eventsContent)

	// Combine Panels
	topRow := lipgloss.JoinHorizontal(lipgloss.Top, pendingPanel, activePanel, completePanel)
	mainView := lipgloss.JoinVertical(lipgloss.Left, topRow, eventsPanel)

	// Header
	header := titleStyle.Render("💠 CLAUDE ORCHESTRA | CONTROL CENTER v2.2")

	// Footer (Commands)
    var footer string
	if m.InputMode {
		inputView := m.Input.View()
        helpText := "[Enter]: Confirm    [Esc]: Cancel"
        footer = fmt.Sprintf("%s\n%s", inputView, helpText)
	} else {
        cmdStatus := lipgloss.NewStyle().Foreground(special).Render("(Command Mode)")
        helpText := "[Tab] Switch  [A] Add  [S] Start  [T] Stop  [C] Complete  [L] Logs  [E] Edit  [W] Watch  [R] Scan  [Q] Exit"
        footer = fmt.Sprintf("%s\n%s", cmdStatus, helpText)
	}
    
    footerView := lipgloss.NewStyle().Foreground(subtle).MarginTop(1).Render(footer)

    content := lipgloss.JoinVertical(lipgloss.Left, header, mainView, footerView)
	return docStyle.Render(content)
}
