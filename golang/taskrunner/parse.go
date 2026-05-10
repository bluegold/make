package taskrunner

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var variableLinePattern = regexp.MustCompile(`^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$`)

func ParseFile(taskfile string) (*Program, error) {
	absPath, err := filepath.Abs(taskfile)
	if err != nil {
		return nil, err
	}

	if _, err := os.Stat(absPath); err != nil {
		return nil, fmt.Errorf("Error: File '%s' not found.", absPath)
	}

	file, err := os.Open(absPath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	program := NewProgram()
	scanner := bufio.NewScanner(file)
	currentTask := ""

	for scanner.Scan() {
		line := strings.TrimRight(scanner.Text(), "\r\n")
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}

		if len(line) > 0 && (line[0] == '\t' || line[0] == ' ') {
			if currentTask == "" {
				continue
			}
			cmd := strings.TrimSpace(line)
			if cmd != "" {
				task := program.Tasks[currentTask]
				task.Commands = append(task.Commands, cmd)
			}
			continue
		}

		if matches := variableLinePattern.FindStringSubmatch(line); matches != nil {
			program.Variables[matches[1]] = matches[2]
			currentTask = ""
			continue
		}

		if strings.Contains(line, ":") {
			parts := strings.SplitN(line, ":", 2)
			target := strings.TrimSpace(parts[0])
			if target == "" {
				currentTask = ""
				continue
			}
			deps := strings.Fields(parts[1])
			task, exists := program.Tasks[target]
			if !exists {
				task = &Task{Name: target}
				program.Tasks[target] = task
				program.TaskOrder = append(program.TaskOrder, target)
			}
			task.Dependencies = append(task.Dependencies, deps...)
			if program.FirstTarget == "" {
				program.FirstTarget = target
			}
			currentTask = target
			continue
		}

		currentTask = ""
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return program, nil
}
