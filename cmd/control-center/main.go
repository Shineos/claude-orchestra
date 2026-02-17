package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
	"shineos/claude-orchestra/internal/ui"
)

func main() {
	// Set up signal handling for graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Create and start the program
	p := tea.NewProgram(ui.InitialModel(), tea.WithAltScreen(), tea.WithMouseCellMotion())

	// Run program in a goroutine to handle signals
	runErr := make(chan error, 1)
	go func() {
		_, err := p.Run()
		runErr <- err
	}()

	// Wait for either program to finish or signal
	select {
	case err := <-runErr:
		if err != nil {
			fmt.Printf("Alas, there's been an error: %v", err)
			os.Exit(1)
		}
	case sig := <-sigChan:
		// Signal received - ensure clean shutdown
		fmt.Printf("\nReceived signal: %v. Shutting down cleanly...\n", sig)
		p.Quit()
		// Wait a bit for cleanup
		<-runErr
	}
}
