package taskrunner

import (
	"fmt"
	"os"
	"regexp"
	"strings"
)

type ExpandOptions struct {
	ExtraVars    map[string]string
	AllowSpecial bool
}

var variablePattern = regexp.MustCompile(`\$\(([^)]+)\)|\$([@<^])`)

func ExpandVariables(text string, variables map[string]string, options *ExpandOptions) (string, error) {
	if options == nil {
		options = &ExpandOptions{}
	}
	return expandVariables(text, variables, options, map[string]bool{})
}

func expandVariables(text string, variables map[string]string, options *ExpandOptions, stack map[string]bool) (string, error) {
	var builder strings.Builder
	cursor := 0

	for cursor < len(text) {
		loc := variablePattern.FindStringSubmatchIndex(text[cursor:])
		if loc == nil {
			builder.WriteString(text[cursor:])
			break
		}

		builder.WriteString(text[cursor : cursor+loc[0]])
		name := ""
		switch {
		case loc[2] != -1:
			name = text[cursor+loc[2] : cursor+loc[3]]
		case loc[4] != -1:
			name = text[cursor+loc[4] : cursor+loc[5]]
		}
		value, err := resolveVariable(name, variables, options, stack)
		if err != nil {
			return "", err
		}
		builder.WriteString(value)
		cursor += loc[1]
	}

	return builder.String(), nil
}

func resolveVariable(name string, variables map[string]string, options *ExpandOptions, stack map[string]bool) (string, error) {
	if options != nil && options.ExtraVars != nil {
		if value, ok := options.ExtraVars[name]; ok {
			return value, nil
		}
	}

	if isSpecialVariable(name) && (options == nil || !options.AllowSpecial) {
		return "", fmt.Errorf("Error: Special variable '%s' is not supported.", name)
	}

	if value, ok := os.LookupEnv(name); ok {
		return value, nil
	}

	if stack[name] {
		return "", fmt.Errorf("Error: Circular variable reference detected involving '%s'", name)
	}

	if value, ok := variables[name]; ok {
		stack[name] = true
		defer delete(stack, name)
		return expandVariables(value, variables, options, stack)
	}

	return "", nil
}

func isSpecialVariable(name string) bool {
	switch name {
	case "@", "<", "^":
		return true
	default:
		return false
	}
}

func NormalizeProgram(program *Program) (*Program, error) {
	normalized := NewProgram()
	for key, value := range program.Variables {
		normalized.Variables[key] = value
	}

	for _, rawName := range program.TaskOrder {
		task := program.Tasks[rawName]
		name, err := ExpandVariables(task.Name, normalized.Variables, nil)
		if err != nil {
			return nil, err
		}

		dependencies := make([]string, 0, len(task.Dependencies))
		for _, dep := range task.Dependencies {
			expanded, err := ExpandVariables(dep, normalized.Variables, nil)
			if err != nil {
				return nil, err
			}
			dependencies = append(dependencies, strings.Fields(expanded)...)
		}

		normalized.Tasks[name] = &Task{
			Name:         name,
			Dependencies: dependencies,
			Commands:     append([]string{}, task.Commands...),
		}
		normalized.TaskOrder = append(normalized.TaskOrder, name)
	}

	if program.FirstTarget != "" {
		firstTarget, err := ExpandVariables(program.FirstTarget, normalized.Variables, nil)
		if err != nil {
			return nil, err
		}
		normalized.FirstTarget = firstTarget
	}

	return normalized, nil
}
