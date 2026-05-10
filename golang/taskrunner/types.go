package taskrunner

type Task struct {
	Name         string
	Dependencies []string
	Commands     []string
}

type Program struct {
	Variables   map[string]string
	Tasks       map[string]*Task
	TaskOrder   []string
	FirstTarget string
}

func NewProgram() *Program {
	return &Program{
		Variables: make(map[string]string),
		Tasks:     make(map[string]*Task),
		TaskOrder: make([]string, 0),
	}
}
