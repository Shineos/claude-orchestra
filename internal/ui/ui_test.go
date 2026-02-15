package ui

import (
	"testing"
	"github.com/charmbracelet/bubbletea"
)

func TestUpdate(t *testing.T) {
	m := InitialModel()

	// Scenario 1: Navigation
	// Initial Tab should be 0 (Pending)
	if m.Tab != 0 {
		t.Errorf("Expected Tab 0, got %d", m.Tab)
	}

	// Press Tab -> Tab 1 (Active)
	m, _ = updateModel(m, tea.KeyMsg{Type: tea.KeyTab})
	if m.Tab != 1 {
		t.Errorf("Expected Tab 1 after Tab press, got %d", m.Tab)
	}

	// Scenario 2: Add Task Mode
	// Press 'a' -> InputMode true
	m, _ = updateModel(m, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("a")})
	if !m.InputMode {
		t.Errorf("Expected InputMode true after 'a', got false")
	}

	// Press Esc -> InputMode false
	m, _ = updateModel(m, tea.KeyMsg{Type: tea.KeyEsc})
	if m.InputMode {
		t.Errorf("Expected InputMode false after Esc, got true")
	}
}

// Helper to cast model back to MainModel
func updateModel(m MainModel, msg tea.Msg) (MainModel, tea.Cmd) {
	newM, cmd := m.Update(msg)
	return newM.(MainModel), cmd
}
