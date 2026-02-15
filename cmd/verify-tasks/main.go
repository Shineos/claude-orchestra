package main

import (
	"fmt"
	"os"
	"strings"
	"shineos/claude-orchestra/internal/orchestrator"
	
	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	// Change directory to target env for testing
	targetDir := "/Users/grace/dev/shineos/shineos-saas-starter"
	err := os.Chdir(targetDir)
	if err != nil {
		fmt.Printf("Error changing dir: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("Running scenario test in %s\n", targetDir)

	// 1. Add Task
	fmt.Println(">> Adding Task: 'Integration Test Task'")
	performCmd(orchestrator.AddTaskCmd("Integration Test Task"))




	// 2. Fetch and Find Task ID
	tasks := fetchTasks()
	var testTask *orchestrator.Task
	for i := range tasks {
		if strings.EqualFold(tasks[i].Description, "Integration Test Task") && tasks[i].Status == "pending" {
			testTask = &tasks[i]
			break
		}
	}
	if testTask == nil {
		fmt.Println("FAILED: Task not found after adding")
		os.Exit(1)
	}
	fmt.Printf(">> Task Added. ID: %d\n", testTask.ID)

	// 3. Start Task
	fmt.Printf(">> Starting Task #%d\n", testTask.ID)
	performCmd(orchestrator.StartTaskCmd(testTask.ID))
	
	// Verify Status
	tasks = fetchTasks()
	found := false
	for _, t := range tasks {
		if t.ID == testTask.ID {
			if t.Status != "in_progress" {
				fmt.Printf("FAILED: Expected status 'in_progress', got '%s'\n", t.Status)
				os.Exit(1)
			}
			found = true
			fmt.Println(">> Task Started successfully (Status: in_progress)")
			break
		}
	}
	if !found {
		fmt.Println("FAILED: Task lost after starting")
		os.Exit(1)
	}

	// 4. Complete Task
	fmt.Printf(">> Completing Task #%d\n", testTask.ID)
	performCmd(orchestrator.CompleteTaskCmd(testTask.ID))

	// Verify Status
	tasks = fetchTasks()
	found = false
	for _, t := range tasks {
		if t.ID == testTask.ID {
			if t.Status != "completed" {
				fmt.Printf("FAILED: Expected status 'completed', got '%s'\n", t.Status)
				os.Exit(1)
			}
			found = true
			fmt.Println(">> Task Completed successfully (Status: completed)")
			break
		}
	}

	fmt.Println(">> SCENARIO TEST PASSED")
}

func performCmd(cmd tea.Cmd) {
	msg := cmd()
	if errMsg, ok := msg.(orchestrator.ErrorMsg); ok {
		fmt.Printf("Command Failed: %v\n", errMsg)
		os.Exit(1)
	}
}

func fetchTasks() []orchestrator.Task {
	msg := orchestrator.FetchTasksCmd()()
	if tasks, ok := msg.(orchestrator.TaskLoadMsg); ok {
		return []orchestrator.Task(tasks)
	}
	return nil
}
