package ui

import (
	"fmt"
	"strings"

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

    W := m.Width
    H := m.Height

    // 1. DIMENSIONS (v3.5 - Optimized Layout)
    // Horizontal buffer: 4 chars (more space)
    // Vertical buffer: 4 lines
    tW := W - 4
    if tW < 60 { tW = 60 }
    
    tH := H - 4
    if tH < 15 { tH = 15 }
    
    // Height allocation: Header(1) + Board(listH) + Log(logH) + Footer(2) = tH
    logH := (tH * 35) / 100
    if logH < 6 { logH = 6 }
    listH := tH - 3 - logH 

    gapW := 1
    cW1 := (tW - (gapW * 2)) / 3
    cW2 := cW1
    cW3 := tW - (cW1 + cW2) - (gapW * 2)

    // 2. STYLES
    chromeH := 2 
    chromeW := 2 
	sBase := lipgloss.NewStyle().Border(lipgloss.NormalBorder()).BorderForeground(highlight)
	sActive := sBase.Copy().BorderForeground(accent)

    // 3. RENDER PANELS
    m.pendingList.SetSize(cW1 - chromeW, listH - chromeH)
    ps1 := sBase
    if m.Tab == 0 && !m.AddingTask { ps1 = sActive }
    v1 := ps1.Width(cW1).Height(listH).Render(m.pendingList.View())

    m.activeList.SetSize(cW2 - chromeW, listH - chromeH)
    as2 := sBase
    if m.Tab == 1 && !m.AddingTask { as2 = sActive }
    v2 := as2.Width(cW2).Height(listH).Render(m.activeList.View())

    m.completeList.SetSize(cW3 - chromeW, listH - chromeH)
    cs3 := sBase
    if m.Tab == 2 && !m.AddingTask { cs3 = sActive }
    v3 := cs3.Width(cW3).Height(listH).Render(m.completeList.View())

    // Log
    logLinesH := logH - 3
    if logLinesH < 1 { logLinesH = 1 }
    var lLines []string
    for i := 0; i < logLinesH; i++ {
        if i < len(m.events) {
            lLines = append(lLines, "- " + m.events[i])
        }
    }
    lTitle := "SYSTEM LOG"
    vLog := sBase.Width(tW).Height(logH).Render(lTitle + "\n" + strings.Join(lLines, "\n"))

    // 4. HEADER & FOOTER
	header := lipgloss.NewStyle().Width(tW).Bold(true).Foreground(accent).
        Render(fmt.Sprintf("💠 CLAUDE ORCHESTRA | CONTROL CENTER v1.1   [%dx%d]", W, H))

    var footer string
    if m.AddingTask {
        // Wizard Footer
        title := lipgloss.NewStyle().Foreground(highlight).Bold(true).Render(fmt.Sprintf("STEP %d: ", m.AddingStep))
        var content string
        var hint string

        switch m.AddingStep {
        case 1:
            content = "Describe the task: " + m.Input.View()
            hint = "[Enter] Next  [Esc] Cancel"
        case 2:
            var choices []string
            for i, choice := range m.AgentChoices {
                if i == m.AgentChoiceIndex {
                    choices = append(choices, lipgloss.NewStyle().Background(accent).Foreground(lipgloss.Color("0")).Render(" "+choice+" "))
                } else {
                    choices = append(choices, choice)
                }
            }
            content = "Select Agent: " + strings.Join(choices, "  ")
            hint = "[Tab/Arrows] Change  [Enter] Next  [Esc] Cancel"
        case 3:
            agent := m.PendingTaskAgent
            if agent == "" { agent = "AI (auto)" }
            content = lipgloss.NewStyle().Foreground(special).Render(fmt.Sprintf("CONFIRM: [%s] %s", agent, m.PendingTaskDesc))
            hint = "[Enter] Confirm  [E] Edit Description  [Esc] Cancel"
        }
        footer = lipgloss.JoinVertical(lipgloss.Left, title+content, lipgloss.NewStyle().Foreground(subtle).Render(hint))
    } else {
        // Regular Footer
        fCmd := lipgloss.NewStyle().Foreground(special).Render("(Command Mode)")
        fHnt := "[Tab] Move  [A] Add  [S] Start  [T] Stop  [C] Comp  [L] Logs  [E] Edit  [W] Watch  [O] Open  [Q] Exit"
        if m.InputMode {
            fCmd = m.Input.View()
            fHnt = "[Enter]: Confirm  [Esc]: Cancel"
        }
        footer = lipgloss.JoinVertical(lipgloss.Left, fCmd, fHnt)
    }

    // 5. ASSEMBLY
    hGap := strings.Repeat(" ", gapW)
    mid := lipgloss.JoinHorizontal(lipgloss.Top, v1, hGap, v2, hGap, v3)
    board := lipgloss.JoinVertical(lipgloss.Left, header, mid, vLog, footer)
    
	// 6. FINAL PLACEMENT (Centered but with smaller gutters)
    return lipgloss.Place(W, H, lipgloss.Center, lipgloss.Center, board)
}
