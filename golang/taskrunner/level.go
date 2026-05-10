package taskrunner

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
)

func RunLevel1(taskfile string, target string) error {
	program, err := ParseFile(taskfile)
	if err != nil {
		return err
	}
	if target == "" {
		target = program.FirstTarget
	}
	order, err := ResolveDependencies(program, target)
	if err != nil {
		return err
	}
	return withTaskfileDir(taskfile, func() error {
		return ExecuteSequential(program, order, nil)
	})
}

func RunLevel2(taskfile string, target string) error {
	program, err := ParseFile(taskfile)
	if err != nil {
		return err
	}
	normalized, err := NormalizeProgram(program)
	if err != nil {
		return err
	}
	if target == "" {
		target = normalized.FirstTarget
	}
	order, err := ResolveDependencies(normalized, target)
	if err != nil {
		return err
	}
	return withTaskfileDir(taskfile, func() error {
		return ExecuteSequential(normalized, order, func(command string, _ *Task) (string, error) {
			return ExpandVariables(command, normalized.Variables, nil)
		})
	})
}

func RunLevel3(taskfile string, target string) error {
	program, err := ParseFile(taskfile)
	if err != nil {
		return err
	}
	normalized, err := NormalizeProgram(program)
	if err != nil {
		return err
	}
	if target == "" {
		target = normalized.FirstTarget
	}
	if _, err := ResolveDependencies(normalized, target); err != nil {
		return err
	}
	return withTaskfileDir(taskfile, func() error {
		executor := newParallelExecutor(normalized)
		return executor.run(target)
	})
}

func withTaskfileDir(taskfile string, fn func() error) error {
	absPath, err := filepath.Abs(taskfile)
	if err != nil {
		return err
	}

	cwd, err := os.Getwd()
	if err != nil {
		return err
	}
	defer func() {
		_ = os.Chdir(cwd)
	}()

	if err := os.Chdir(filepath.Dir(absPath)); err != nil {
		return err
	}

	return fn()
}

type parallelExecutor struct {
	program *Program
	mu      sync.Mutex
	futures map[string]*taskFuture
}

type taskFuture struct {
	once sync.Once
	done chan struct{}
	err  error
}

func newParallelExecutor(program *Program) *parallelExecutor {
	return &parallelExecutor{
		program: program,
		futures: make(map[string]*taskFuture),
	}
}

func (e *parallelExecutor) run(target string) error {
	future := e.getFuture(target)
	future.once.Do(func() {
		defer close(future.done)

		task := e.program.Tasks[target]
		if task == nil {
			if _, err := os.Stat(target); err == nil {
				return
			} else if os.IsNotExist(err) {
				return
			} else {
				future.err = err
			}
		}

		var wg sync.WaitGroup
		errs := make(chan error, len(task.Dependencies))
		for _, dep := range task.Dependencies {
			dep := dep
			wg.Add(1)
			go func() {
				defer wg.Done()
				if err := e.run(dep); err != nil {
					errs <- err
				}
			}()
		}

		wg.Wait()
		close(errs)
		if err := firstError(errs); err != nil {
			future.err = err
			return
		}

		needsUpdate, err := needsUpdate(target, task.Dependencies)
		if err != nil {
			future.err = err
			return
		}
		if !needsUpdate {
			return
		}

		extraVars := map[string]string{
			"@": task.Name,
			"<": firstDependency(task.Dependencies),
			"^": strings.Join(task.Dependencies, " "),
		}

		for _, command := range task.Commands {
			expanded, err := ExpandVariables(command, e.program.Variables, &ExpandOptions{
				ExtraVars:    extraVars,
				AllowSpecial: true,
			})
			if err != nil {
				future.err = err
				return
			}
			if err := runCommand(expanded); err != nil {
				future.err = err
				return
			}
		}
	})

	<-future.done
	return future.err
}

func (e *parallelExecutor) getFuture(target string) *taskFuture {
	e.mu.Lock()
	defer e.mu.Unlock()

	if future, ok := e.futures[target]; ok {
		return future
	}

	future := &taskFuture{done: make(chan struct{})}
	e.futures[target] = future
	return future
}

func firstError(errs <-chan error) error {
	for err := range errs {
		if err != nil {
			return err
		}
	}
	return nil
}

func needsUpdate(target string, dependencies []string) (bool, error) {
	targetInfo, err := os.Stat(target)
	if err != nil {
		if os.IsNotExist(err) {
			return true, nil
		}
		return false, err
	}

	for _, dep := range dependencies {
		depInfo, err := os.Stat(dep)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return false, err
		}
		if depInfo.ModTime().After(targetInfo.ModTime()) {
			return true, nil
		}
	}

	return false, nil
}

func firstDependency(dependencies []string) string {
	if len(dependencies) == 0 {
		return ""
	}
	return dependencies[0]
}
