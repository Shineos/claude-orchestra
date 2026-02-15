package orchestrator

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"

	tea "github.com/charmbracelet/bubbletea"
)

// Task represents a task in the system
type Task struct {
	ID          int    `json:"id"`
	Description string `json:"description"`
	Status      string `json:"status"` // pending, in_progress, completed, failed
	Agent       string `json:"agent"`
	Priority    string `json:"priority"`
}

type TasksData struct {
	Tasks []Task `json:"tasks"`
}

// Msg types
type TaskLoadMsg []Task
type ErrorMsg error

// FetchTasksCmd reads tasks.json and returns a message
func FetchTasksCmd() tea.Cmd {
	return func() tea.Msg {
		// Assuming we are running from project root or know where .claude is
		// Try to find .claude/tasks.json. 
		// For now, let's hardcode a path or look in current dir/.claude
		path := ".claude/tasks.json"
		if _, err := os.Stat(path); os.IsNotExist(err) {
			// Fallback for testing from different dirs
			path = "../../.claude/tasks.json" 
		}

		data, err := os.ReadFile(path)
		if err != nil {
			return ErrorMsg(fmt.Errorf("failed to read tasks.json: %w", err))
		}

		var tasksData TasksData
		if err := json.Unmarshal(data, &tasksData); err != nil {
			return ErrorMsg(fmt.Errorf("failed to list tasks: %w", err))
		}
		return TaskLoadMsg(tasksData.Tasks)
	}
}

// AddTaskCmd executes the orchestrator script to add a task
func AddTaskCmd(desc string) tea.Cmd {
	return func() tea.Msg {
		scriptPath := findScriptPath()

		// Execute orchestrator.sh add "desc"
		// We set USE_AI=false to avoid interactive prompts in this context if possible, 
		// but typically 'add' might be interactive. 
		// For the TUI, we probably want non-interactive add if we supply description.
		// Let's use ORCH_AUTO_CONFIRM=yes for now to simplify.
		cmd := exec.Command("bash", scriptPath, "add", desc)
		cmd.Env = append(os.Environ(), "ORCH_AUTO_CONFIRM=yes", "USE_AI=false", "ORCH_NO_AUTO_LAUNCH=yes")
		
		output, err := cmd.CombinedOutput()
		if err != nil {
			return ErrorMsg(fmt.Errorf("add task failed: %v\nOutput: %s", err, output))
		}

		// After adding, we should probably fetch tasks again
		// But for now, let's just return a success msg or re-fetch
		return FetchTasksCmd()()
	}
}

// StartTaskCmd executes orchestrator.sh start <id>
func StartTaskCmd(id int) tea.Cmd {
	return func() tea.Msg {
		scriptPath := findScriptPath()
		cmd := exec.Command("bash", scriptPath, "start", fmt.Sprintf("%d", id))
		output, err := cmd.CombinedOutput()
		if err != nil {
			return ErrorMsg(fmt.Errorf("start task failed: %v\nOutput: %s", err, output))
		}
		return FetchTasksCmd()()
	}
}

// CompleteTaskCmd executes orchestrator.sh complete <id>
func CompleteTaskCmd(id int) tea.Cmd {
	return func() tea.Msg {
		scriptPath := findScriptPath()
		cmd := exec.Command("bash", scriptPath, "complete", fmt.Sprintf("%d", id))
		output, err := cmd.CombinedOutput()
		if err != nil {
			return ErrorMsg(fmt.Errorf("complete task failed: %v\nOutput: %s", err, output))
		}
		return FetchTasksCmd()()
	}
}

// StopTaskCmd executes orchestrator.sh stop <id>
func StopTaskCmd(id int) tea.Cmd {
	return func() tea.Msg {
		scriptPath := findScriptPath()
		cmd := exec.Command("bash", scriptPath, "stop", fmt.Sprintf("%d", id))
		output, err := cmd.CombinedOutput()
		if err != nil {
			return ErrorMsg(fmt.Errorf("stop task failed: %v\nOutput: %s", err, output))
		}
		return FetchTasksCmd()()
	}
}

// RemoveTaskCmd executes orchestrator.sh remove-task <id>
func RemoveTaskCmd(id int) tea.Cmd {
	return func() tea.Msg {
		scriptPath := findScriptPath()
		cmd := exec.Command("bash", scriptPath, "remove-task", fmt.Sprintf("%d", id))
		// We might need to auto-confirm if it asks "Are you sure?"
		// But usually orchestration commands are non-interactive unless critical.
		// Let's assume non-interactive or pipe "y" if needed.
		// Checking remove_task: it asks for confirmation if task count > 0 (for agents).
		// Wait, remove_task removes a task by ID.
		// "remove_agent" asks for confirmation.
		output, err := cmd.CombinedOutput()
		if err != nil {
			return ErrorMsg(fmt.Errorf("remove task failed: %v\nOutput: %s", err, output))
		}
		return FetchTasksCmd()()
	}
}

// LogsTuiCmd executes orchestrator.sh logs-tui
// This runs an interactive TUI, so we need tea.ExecProcess
func LogsTuiCmd() tea.Cmd {
	scriptPath := findScriptPath()
	c := exec.Command("bash", scriptPath, "logs-tui", "-f")
    c.Stdin = os.Stdin
    c.Stdout = os.Stdout
    c.Stderr = os.Stderr
	return tea.ExecProcess(c, func(err error) tea.Msg {
		if err != nil {
			return ErrorMsg(err)
		}
		return nil
	})
}

func findScriptPath() string {
    // When running from project root (typical case)
    if _, err := os.Stat(".claude/scripts/orchestrator.sh"); err == nil {
        return ".claude/scripts/orchestrator.sh"
    }

    // When running from installed bin location (~/project/.claude/bin/control-center)
    // We need to look up one level to .claude/scripts/orchestrator.sh
    if _, err := os.Stat("../scripts/orchestrator.sh"); err == nil {
        return "../scripts/orchestrator.sh"
    }
    
    // Absolute fallback (User's specific path if all else fails - risky but useful for debugging)
    // Better: Assume if we are in bin, scripts is adjacent.
    // If we are control-center binary, look relative to executable?
    // For now, let's return a best guess that covers the install.sh case.
    // install.sh puts binary in .claude/bin
    // scripts are in .claude/scripts
    return "../scripts/orchestrator.sh"
}
