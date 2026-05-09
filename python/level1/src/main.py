import sys
import os
import subprocess

class Task:
    def __init__(self, name, dependencies=None, commands=None):
        self.name = name
        self.dependencies = dependencies or []
        self.commands = commands or []

    def __repr__(self):
        return f"Task({self.name}, deps={self.dependencies}, cmds={self.commands})"

class TaskRunner:
    def __init__(self):
        self.tasks = {}
        self.first_target = None

    def parse_file(self, filepath):
        if not os.path.exists(filepath):
            print(f"Error: File '{filepath}' not found.")
            sys.exit(1)

        with open(filepath, 'r') as f:
            current_task = None
            for line in f:
                line = line.rstrip()
                if not line or line.startswith('#'):
                    continue

                if line[0] in ('\t', ' '):
                    # Command (indented line)
                    if current_task:
                        command = line.strip()
                        if command:
                            self.tasks[current_task].commands.append(command)
                    continue

                if ':' in line:
                    # Target: Dependencies
                    parts = line.split(':')
                    target = parts[0].strip()
                    deps = [d.strip() for d in parts[1].split() if d.strip()]
                    
                    self.tasks[target] = Task(target, deps)
                    if self.first_target is None:
                        self.first_target = target
                    current_task = target

    def resolve_dependencies(self, target, visited=None, stack=None):
        if visited is None:
            visited = set()
        if stack is None:
            stack = set()

        if target in stack:
            print(f"Error: Circular dependency detected involving '{target}'")
            sys.exit(1)
        
        if target in visited:
            return []

        if target not in self.tasks:
            # It might be a file on disk without a specific task
            if os.path.exists(target):
                visited.add(target)
                return []
            else:
                print(f"Error: No rule to make target '{target}'")
                sys.exit(1)

        stack.add(target)
        order = []
        for dep in self.tasks[target].dependencies:
            order.extend(self.resolve_dependencies(dep, visited, stack))
        
        stack.remove(target)
        visited.add(target)
        order.append(target)
        return order

    def execute(self, target_order):
        for target_name in target_order:
            task = self.tasks.get(target_name)
            if not task:
                continue
            
            for cmd in task.commands:
                print(f"Executing: {cmd}")
                sys.stdout.flush()
                result = subprocess.run(cmd, shell=True)
                if result.returncode != 0:
                    print(f"Error: Command '{cmd}' failed with exit code {result.returncode}")
                    sys.exit(result.returncode)

def main():
    args = sys.argv[1:]
    taskfile = "Taskfile"
    target = None

    if len(args) >= 1:
        # Check if first arg is a file
        if os.path.exists(args[0]):
            taskfile = args[0]
            if len(args) >= 2:
                target = args[1]
        else:
            target = args[0]

    runner = TaskRunner()
    runner.parse_file(taskfile)
    
    if target is None:
        target = runner.first_target
    
    if target not in runner.tasks and not os.path.exists(target):
        print(f"Error: Target '{target}' not found in '{taskfile}'")
        sys.exit(1)

    order = runner.resolve_dependencies(target)
    runner.execute(order)

if __name__ == "__main__":
    main()
