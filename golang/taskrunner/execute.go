package taskrunner

import (
	"fmt"
	"os/exec"
	"strings"
)

type CommandExpander func(command string, task *Task) (string, error)

func ExecuteSequential(program *Program, order []string, expander CommandExpander) error {
	if expander == nil {
		expander = func(command string, _ *Task) (string, error) {
			return command, nil
		}
	}

	for _, targetName := range order {
		task := program.Tasks[targetName]
		if task == nil {
			continue
		}
		for _, command := range task.Commands {
			expanded, err := expander(command, task)
			if err != nil {
				return err
			}
			if err := runCommand(expanded); err != nil {
				return err
			}
		}
	}

	return nil
}

func runCommand(command string) error {
	silent := false
	trimmed := strings.TrimSpace(command)
	if strings.HasPrefix(trimmed, "@") {
		silent = true
		trimmed = strings.TrimSpace(strings.TrimPrefix(trimmed, "@"))
	}
	if trimmed == "" {
		return nil
	}

	if !silent {
		fmt.Printf("Executing: %s\n", trimmed)
	}

	out, err := exec.Command("sh", "-c", trimmed).CombinedOutput()
	if err != nil {
		return fmt.Errorf("Error: Command '%s' failed: %w", trimmed, err)
	}
	if len(out) > 0 {
		fmt.Print(string(out))
	}

	return nil
}
