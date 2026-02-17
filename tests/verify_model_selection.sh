#!/bin/bash
# Verify agent.sh model selection logic

# Mock PROJECT_ROOT and SCRIPT_DIR if needed, but sourcing agent.sh should set SCRIPT_DIR relative to itself.
# We need to source it. agent.sh executes main logic at end. We can bypass it by setting AGENT_NAME="--help" maybe?
# Or just copy the functions to test them.
# agent.sh has "if [[ -n "$AGENT_NAME" ... case ...". If we source it without args, AGENT_NAME is empty.
# So it might just fall through to usage?
# Let's try sourcing it.

SCRIPT_DIR="/Users/grace/dev/shineos/claude-orchestra/.claude"
source "$SCRIPT_DIR/agent.sh" "" ""

echo "--- Testing get_config_value ---"
OPUS_VAL=$(get_config_value "ANTHROPIC_DEFAULT_OPUS_MODEL")
echo "ANTHROPIC_DEFAULT_OPUS_MODEL from settings: '$OPUS_VAL'"

echo "--- Testing Model Variables ---"
echo "OPUS_MODEL: $OPUS_MODEL"
echo "SONNET_MODEL: $SONNET_MODEL"
echo "HAIKU_MODEL: $HAIKU_MODEL"

echo "--- Testing Model Selection Logic ---"
# Mock execute_task logic for selection
test_selection() {
    local agent=$1
    local model=""
    case "$agent" in
        planner|architect|orchestrator|root-cause-verifier)
            model="$OPUS_MODEL"
            ;;
        frontend|backend|docs)
            model="$SONNET_MODEL"
            ;;
        tests|tester|reviewer)
            model="$HAIKU_MODEL"
            ;;
        *)
            model="$SONNET_MODEL"
            ;;
    esac
    echo "Agent '$agent' -> Model '$model'"
}

test_selection "architect"
test_selection "backend"
test_selection "tests"
test_selection "unknown"
