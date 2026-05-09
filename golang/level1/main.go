package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type Task struct {
	Name         string
	Dependencies []string
	Commands     []string
}

type TaskRunner struct {
	Tasks       map[string]*Task
	FirstTarget string
}

func NewTaskRunner() *TaskRunner {
	return &TaskRunner{
		Tasks:       make(map[string]*Task),
		FirstTarget: "",
	}
}

func (tr *TaskRunner) parseFile(taskfile string) error {
	absPath, err := filepath.Abs(taskfile)
	if err != nil {
		return err
	}

	if _, err := os.Stat(absPath); err != nil {
		return fmt.Errorf("Error: File '%s' not found.", absPath)
	}

	file, err := os.Open(absPath)
	if err != nil {
		return err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	currentTask := ""
	for scanner.Scan() {
		line := strings.TrimRight(scanner.Text(), "\r\n")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if len(line) > 0 && (line[0] == '\t' || line[0] == ' ') {
			// Command (indented line)
			if currentTask != "" {
				cmd := strings.TrimSpace(line)
				if cmd != "" {
					tr.Tasks[currentTask].Commands = append(tr.Tasks[currentTask].Commands, cmd)
				}
			}
			continue
		}

		if strings.Contains(line, ":") {
			// Target: Dependencies
			parts := strings.SplitN(line, ":", 2)
			target := strings.TrimSpace(parts[0])
			deps := strings.Fields(parts[1])

			tr.Tasks[target] = &Task{
				Name:         target,
				Dependencies: deps,
			}
			if tr.FirstTarget == "" {
				tr.FirstTarget = target
			}
			currentTask = target
		}
	}

	if err := scanner.Err(); err != nil {
		return err
	}

	return nil
}

func (tr *TaskRunner) resolveDependencies(target string, visited map[string]bool, stack map[string]bool) ([]string, error) {
	if target == "" {
		return []string{}, nil
	}

	if stack[target] {
		return []string{}, fmt.Errorf("Error: Circular dependency detected involving '%s'", target)
	}

	visited[target] = true
	stack[target] = true

	task := tr.Tasks[target]
	if task == nil {
		return []string{}, fmt.Errorf("Error: Unknown target '%s'", target)
	}

	var order []string
	for _, dep := range task.Dependencies {
		deps, err := tr.resolveDependencies(dep, visited, stack)
		if err != nil {
			return []string{}, err
		}
		order = append(order, deps...)
	}

	// Add current task after dependencies
	order = append(order, target)

	// Remove cycle tracking for current task
	delete(stack, target)

	return order, nil
}

func (tr *TaskRunner) execute(targetOrder []string) error {
	for _, targetName := range targetOrder {
		task := tr.Tasks[targetName]
		if task == nil {
			continue
		}

		for _, cmd := range task.Commands {
			fmt.Printf("Executing: %s\n", cmd)
			out, err := exec.Command("sh", "-c", cmd).CombinedOutput()
			if err != nil {
				fmt.Printf("Error: Command '%s' failed\n", cmd)
				os.Exit(1)
			}
			if string(out) != "" {
				fmt.Print(out)
			}
		}
	}

	return nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: program <taskfile> [target]")
		os.Exit(1)
	}

	taskfile := os.Args[1]
	
	// Change to taskfile directory before parsing
	taskfileDir := filepath.Dir(taskfile)
	os.Chdir(taskfileDir)
	
	tr := NewTaskRunner()
	if err := tr.parseFile(taskfile); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	target := ""
	if len(os.Args) > 2 {
		target = os.Args[2]
	}

	// If no target specified, use first target
	if target == "" {
		target = tr.FirstTarget
	}

	order, err := tr.resolveDependencies(target, make(map[string]bool), make(map[string]bool))
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	if err := tr.execute(order); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
