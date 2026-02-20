package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"shineos/claude-orchestra/internal/ui"
)

func main() {
	// Create and start the program
	p := tea.NewProgram(ui.InitialModel(), tea.WithAltScreen(), tea.WithMouseCellMotion())

    if _, err := p.Run(); err != nil {
		fmt.Printf("Alas, there's been an error: %v", err)
		os.Exit(1)
	}
}
