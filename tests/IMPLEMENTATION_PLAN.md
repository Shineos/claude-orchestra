# Implementation Plan: Dashboard Fixes

## Root Cause Analysis

### 1. Zombie Process Issue (CRITICAL)
**Problem**: 17+ zombie control-center processes in 'UE' state

**Root Cause**:
- `tea.ExecProcess()` in `openEditor()` and `LogsTuiCmd()` spawns subprocesses
- When TUI exits abruptly (Ctrl+C), subprocesses aren't properly cleaned up
- Bubble Tea's cleanup mechanism may not be properly invoked

**Files Affected**:
- `internal/ui/update.go:452-455` (openEditor)
- `internal/orchestrator/client.go:244-261` (LogsTuiCmd)

### 2. Task Loading Issue
**Problem**: Tasks exist in `tasks.json` but TUI shows "No items"

**Root Cause**:
- `tasksToItems()` filters by specific statuses only
- Pending list: only "pending" status
- Active list: only "in_progress" and "failed" statuses
- Tasks with "completed", "stopped", or other statuses are hidden
- Tasks with empty descriptions show but look broken

**Files Affected**:
- `internal/ui/update.go:346-348` (TaskLoadMsg handler)
- `internal/ui/update.go:393-429` (tasksToItems function)

### 3. Stop Task Failing
**Problem**: "Failed to stop task" error in tests

**Root Cause**:
- `StopTaskCmd` requires task to have an agent assigned
- If agent is null or not running, `stop_agent()` fails silently
- No proper error handling for edge cases

**Files Affected**:
- `internal/orchestrator/client.go:103-114` (StopTaskCmd)
- `.claude/scripts/orchestrator.sh:3311-3345` (stop command)

### 4. Empty Task Descriptions
**Problem**: Tasks with empty descriptions can be created

**Root Cause**:
- No validation in `AddTask` input handling
- Empty strings pass through to JSON

**Files Affected**:
- `internal/ui/update.go:145-187` (Add Task handling)

---

## Implementation Plan

### Phase 1: Fix Zombie Process Issue (HIGHEST PRIORITY)

#### 1.1 Add Signal Handler for Proper Cleanup
**File**: `internal/ui/main.go` (create if needed)

```go
// Add signal handler to catch SIGINT/SIGTERM
// Ensure all subprocesses are terminated before exit
```

#### 1.2 Track Spawned Processes
**File**: `internal/ui/model.go`

```go
type MainModel struct {
    // ... existing fields ...
    spawnedCmds []*exec.Cmd  // Track all spawned processes
}
```

#### 1.3 Cleanup Function
**File**: `internal/ui/update.go`

```go
func (m MainModel) cleanupSubprocesses() {
    for _, cmd := range m.spawnedCmds {
        if cmd.Process != nil {
            cmd.Process.Kill()
            cmd.Process.Wait()
        }
    }
}
```

#### 1.4 Modify tea.ExecProcess Usage
**File**: `internal/ui/update.go:452-455`

Instead of relying solely on `tea.ExecProcess`, add explicit cleanup.

### Phase 2: Fix Task Loading

#### 2.1 Show All Relevant Tasks
**File**: `internal/ui/update.go:346-348`

Change to show all non-completed tasks in pending, and recently completed in active.

#### 2.2 Add Empty Description Handling
**File**: `internal/ui/update.go:393-429`

Handle tasks with empty descriptions gracefully.

### Phase 3: Fix Stop Task

#### 3.1 Add Better Error Handling
**File**: `internal/orchestrator/client.go:103-114`

Add checks for agent existence before calling stop.

#### 3.2 Update Shell Script
**File**: `.claude/scripts/orchestrator.sh:3311-3345`

Add better error messages and handling.

### Phase 4: Add Task Validation

#### 4.1 Validate Input
**File**: `internal/ui/update.go:145-187`

Reject empty task descriptions.

---

## Test Plan

Test all fixes in `/Users/grace/dev/shineos/shineos-saas-starter`:
1. Start dashboard
2. Add task (with valid description)
3. Try to add empty task (should fail)
4. Start task
5. Stop task
6. View logs
7. Edit task
8. Exit dashboard
9. Verify with `ps aux | grep control-center | grep UE` - should be 0

---

## Priority Order

1. **Phase 1**: Fix zombie processes (blocking)
2. **Phase 2**: Fix task loading (high visibility)
3. **Phase 3**: Fix stop task (usability)
4. **Phase 4**: Add validation (quality)
