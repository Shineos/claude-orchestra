package orchestrator

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
)

// Task represents a task in the system
type Task struct {
	ID          int    `json:"id"`
	Description string `json:"description"`
	Status      string `json:"status"` // pending, in_progress, completed, failed
	Agent       string `json:"agent"`
	Priority    string `json:"priority"`
	UpdatedAt   string `json:"updated_at"`
}

type TasksData struct {
	Tasks  []Task `json:"tasks"`
	LastID int    `json:"last_id"`
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

// AddTaskCmd executes the orchestrator script to add a task, optionally with an agent
func AddTaskCmd(desc string, agent string) tea.Cmd {
	scriptPath := findScriptPath()
	args := []string{scriptPath, "add", desc}
	if agent != "" {
		args = append(args, agent)
	}

	c := exec.Command("bash", args...)
	// Remove ORCH_AUTO_CONFIRM=yes to allow interactive mode
	// Remove USE_AI=false to allow AI usage if configured (or keep it if we want speed?)
	// Actually, the user wants interactive agent selection, so we should allow interaction.
	// We should probably NOT force any env vars that disable interaction.
	// However, we might want to keep ORCH_NO_AUTO_LAUNCH=yes if we don't want it to auto launch.
	// But let's remove them to match standard behavior for now, or just keep ORCH_NO_AUTO_LAUNCH.
	// The user's goal is agent selection.
	c.Env = os.Environ()
	// If we want to force interactive mode for agent selection, we might need to ensure
	// we don't pass -y or similar flags if they existed. But here we just used to set env vars.

	c.Stdin = os.Stdin
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr

	return tea.ExecProcess(c, func(err error) tea.Msg {
		// Ignore signal errors (Ctrl+C is normal cancel)
		if err != nil && !isSignalError(err) {
			return ErrorMsg(err)
		}
		return FetchTasksCmd()()
	})
}

// StartTaskCmd executes orchestrator.sh start <id>
func StartTaskCmd(id int) tea.Cmd {
	return func() tea.Msg {
		scriptPath := findScriptPath()
		cmd := exec.Command("bash", scriptPath, "start", fmt.Sprintf("%d", id))
		output, err := cmd.CombinedOutput()
		if err != nil {
			// エラー時もリフレッシュして画面の状態を同期
			_ = FetchTasksCmd()()
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
			// エラー時もリフレッシュ
			_ = FetchTasksCmd()()
			return ErrorMsg(fmt.Errorf("complete task failed: %v\nOutput: %s", err, output))
		}
		return FetchTasksCmd()()
	}
}

// StopTaskCmd executes orchestrator.sh stop <id>
func StopTaskCmd(id int) tea.Cmd {
	return func() tea.Msg {
		// First, verify the task exists and has an agent
		scriptPath := findScriptPath()

		// Check if task exists and get agent
		checkCmd := exec.Command("bash", scriptPath, "check-task", fmt.Sprintf("%d", id))
		output, err := checkCmd.CombinedOutput()
		if err != nil {
			return ErrorMsg(fmt.Errorf("task #%d not found or error checking: %v\nOutput: %s", id, err, output))
		}

		// Now try to stop
		cmd := exec.Command("bash", scriptPath, "stop", fmt.Sprintf("%d", id))
		output, err = cmd.CombinedOutput()
		if err != nil {
			// エラー時も状態を同期
			_ = FetchTasksCmd()()
			return ErrorMsg(fmt.Errorf("stop task failed: %v\nOutput: %s", err, output))
		}
		return FetchTasksCmd()()
	}
}


// EditTaskCmd updates the description of a task
func EditTaskCmd(id int, newDescription string) tea.Cmd {
	return func() tea.Msg {
		// Calculate tasks.json path (same logic as FetchTasksCmd)
		path := ".claude/tasks.json"
		if _, err := os.Stat(path); os.IsNotExist(err) {
			path = "../../.claude/tasks.json"
		}

		data, err := os.ReadFile(path)
		if err != nil {
			return ErrorMsg(fmt.Errorf("failed to read tasks.json for editing: %w", err))
		}

		// Use Decoder with UseNumber to preserve numeric precision/type
		var root map[string]interface{}
		decoder := json.NewDecoder(bytes.NewReader(data))
		decoder.UseNumber()
		if err := decoder.Decode(&root); err != nil {
			return ErrorMsg(fmt.Errorf("failed to parse tasks.json for editing: %w", err))
		}

        tasksList, ok := root["tasks"].([]interface{})
        if !ok {
             return ErrorMsg(fmt.Errorf("invalid tasks.json format: tasks field missing or not an array"))
        }

		// Find and update task
		found := false
		for _, item := range tasksList {
            taskMap, ok := item.(map[string]interface{})
            if !ok {
                continue
            }
            
            // ID is generic number, handle as json.Number if UseNumber() was used
            idVal := taskMap["id"]
            var taskID int
            switch v := idVal.(type) {
            case json.Number:
                 i, _ := v.Int64()
                 taskID = int(i)
            case float64:
                 taskID = int(v)
            case int:
                 taskID = v
            }
            
            if taskID == id {
                taskMap["description"] = newDescription
                found = true
                break
            }
		}

		if !found {
			return ErrorMsg(fmt.Errorf("task #%d not found", id))
		}
        
        // No need to re-assign tasksList to root["tasks"] because slice elements are pointers/references to map?
        // Wait, slice of interface{} contains maps. Maps are references. So modifying taskMap works.

		// Write back to file
		updatedData, err := json.MarshalIndent(root, "", "  ")
		if err != nil {
			return ErrorMsg(fmt.Errorf("failed to marshal updated tasks: %w", err))
		}

		if err := os.WriteFile(path, updatedData, 0644); err != nil {
			return ErrorMsg(fmt.Errorf("failed to write tasks.json: %w", err))
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
			// エラー時もリフレッシュ
			_ = FetchTasksCmd()()
			return ErrorMsg(fmt.Errorf("remove task failed: %v\nOutput: %s", err, output))
		}
		return FetchTasksCmd()()
	}
}

// SpawnAgentCmd launches an agent in watch mode
func SpawnAgentCmd(agentName string) tea.Cmd {
	return func() tea.Msg {
		// agent.sh のパスを探す
		scriptPath := ".claude/agent.sh"
		if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
			scriptPath = "../agent.sh"
		}
		if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
			scriptPath = "../../.claude/agent.sh"
		}

		cmd := exec.Command("bash", scriptPath, "watch", agentName)

		// SysProcAttr.Setsid = true により OS レベルで新しいセッションを作成する。
		// これにより TUI の終了シグナル（SIGINT/SIGTERM/SIGHUP）が
		// エージェントプロセスに伝播しなくなる。
		// setsid コマンドに依存せず macOS / Linux 両対応。
		cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}

		// 標準入出力をすべて /dev/null に向けてデーモン化する
		// （ダッシュボードの画面を汚さないため）
		devNull, err := os.OpenFile(os.DevNull, os.O_RDWR, 0)
		if err == nil {
			cmd.Stdin = devNull
			cmd.Stdout = devNull
			cmd.Stderr = devNull
		}

		if err := cmd.Start(); err != nil {
			return ErrorMsg(fmt.Errorf("failed to spawn agent %s: %w", agentName, err))
		}

		// プロセスを背後に残すので Wait はしない
		// ステータスを即座に更新（[RUNNING] 表示にするため）するためにリフレッシュを発行
		return func() tea.Msg { return FetchTasksCmd()() }
	}
}

// OpenTaskCmd opens the tasks.json file or specific task file
func OpenTaskCmd(id int) tea.Cmd {
	return func() tea.Msg {
		path := ".claude/tasks.json"
		if _, err := os.Stat(path); os.IsNotExist(err) {
			path = "../../.claude/tasks.json"
		}

		var cmd *exec.Cmd
		if runtime.GOOS == "darwin" {
			cmd = exec.Command("open", path)
		} else {
			cmd = exec.Command("xdg-open", path)
		}

		if err := cmd.Start(); err != nil {
			return ErrorMsg(fmt.Errorf("open task failed: %v", err))
		}
		return nil
	}
}

// isSignalError checks if the error is due to a signal (e.g., Ctrl+C)
// exit codes 128+n means signal n was received (130 = SIGINT)
func isSignalError(err error) bool {
	if err == nil {
		return false
	}
	if exitErr, ok := err.(*exec.ExitError); ok {
		// 130 = 128 + SIGINT(2), 129 = 128 + SIGHUP(1), etc.
		// Common signals: 1 (SIGHUP), 2 (SIGINT), 15 (SIGTERM)
		exitCode := exitErr.ExitCode()
		return exitCode >= 128 && exitCode <= 143
	}
	return false
}

// LogsTuiCmd executes orchestrator.sh logs-tui with raw-task mode
// Shows the full Claude execution log for the task
func LogsTuiCmd(id int) tea.Cmd {
	scriptPath := findScriptPath()
	// Use --raw-task to show Claude execution logs (verbose level)
	args := []string{scriptPath, "logs-tui", "--raw-task", fmt.Sprintf("%d", id)}
	c := exec.Command("bash", args...)
	c.Stdin = os.Stdin
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	return tea.ExecProcess(c, func(err error) tea.Msg {
		// Ignore signal errors (Ctrl+C is normal exit)
		if err != nil && !isSignalError(err) {
			return ErrorMsg(err)
		}
		return nil
	})
}

// OpenRawLogCmd executes tui-logs.sh --raw-task <id> (same as LogsTuiCmd now)
// Kept for backward compatibility with [V] Verbose command
func OpenRawLogCmd(id int) tea.Cmd {
	scriptPath := findScriptPath()
	args := []string{scriptPath, "logs-tui", "--raw-task", fmt.Sprintf("%d", id)}
	c := exec.Command("bash", args...)
	c.Stdin = os.Stdin
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	return tea.ExecProcess(c, func(err error) tea.Msg {
		// Ignore signal errors (Ctrl+C is normal exit)
		if err != nil && !isSignalError(err) {
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
