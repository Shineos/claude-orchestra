package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"shineos/claude-orchestra/internal/ui"
)

func main() {
	p := tea.NewProgram(ui.InitialModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Alas, there's been an error: %v", err)
		os.Exit(1)
	}
}
