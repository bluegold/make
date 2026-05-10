package taskrunner

import (
	"fmt"
	"os"
)

func ResolveDependencies(program *Program, target string) ([]string, error) {
	if target == "" {
		return []string{}, nil
	}

	visited := make(map[string]bool)
	stack := make(map[string]bool)
	order := make([]string, 0)

	var visit func(string, bool) error
	visit = func(name string, root bool) error {
		if stack[name] {
			return fmt.Errorf("Error: Circular dependency detected involving '%s'", name)
		}
		if visited[name] {
			return nil
		}

		task := program.Tasks[name]
		if task == nil {
			_, statErr := os.Stat(name)
			if statErr == nil {
				return nil
			} else if os.IsNotExist(statErr) {
				if root {
					return fmt.Errorf("Error: Unknown target '%s'", name)
				}
				return nil
			}
			return statErr
		}

		visited[name] = true
		stack[name] = true
		for _, dep := range task.Dependencies {
			if err := visit(dep, false); err != nil {
				return err
			}
		}
		delete(stack, name)
		order = append(order, name)
		return nil
	}

	if err := visit(target, true); err != nil {
		return nil, err
	}

	return order, nil
}
