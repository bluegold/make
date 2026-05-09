import sys
import os
import subprocess
import re

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
        self.variables = {}
        self.first_target = None

    def expand_variables(self, text, expanding=None):
        if expanding is None:
            expanding = []
        
        # Regex to find $(VAR)
        pattern = r'\$\(([^)]+)\)'
        
        def replace(match):
            var_name = match.group(1)
            if var_name in expanding:
                cycle = " -> ".join(expanding + [var_name])
                print(f"Error: Circular variable reference detected: {cycle}")
                sys.exit(1)
            
            val = os.environ.get(var_name, self.variables.get(var_name, ""))
            
            expanding.append(var_name)
            result = self.expand_variables(val, expanding)
            expanding.pop()
            return result
        
        return re.sub(pattern, replace, text)

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

                # Variable definition: KEY = VALUE
                if '=' in line and (':' not in line or line.find('=') < line.find(':')):
                    parts = line.split('=', 1)
                    key = parts[0].strip()
                    value = parts[1].strip()
                    self.variables[key] = value
                    current_task = None
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

    def finalize_parsing(self):
        """Expand variables in target names and dependencies after the whole file is read."""
        final_tasks = {}
        for name, task in self.tasks.items():
            expanded_name = self.expand_variables(name)
            expanded_deps = []
            for d in task.dependencies:
                expanded_val = self.expand_variables(d)
                # Split again in case the variable expanded to multiple items
                expanded_deps.extend(expanded_val.split())
            
            task.name = expanded_name
            task.dependencies = expanded_deps
            final_tasks[expanded_name] = task
        
        self.tasks = final_tasks
        if self.first_target:
            self.first_target = self.expand_variables(self.first_target)

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
            # It might be a file on disk
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
                # Expand variables just before execution (late binding)
                expanded_cmd = self.expand_variables(cmd)
                print(f"Executing: {expanded_cmd}")
                sys.stdout.flush()
                result = subprocess.run(expanded_cmd, shell=True)
                if result.returncode != 0:
                    print(f"Error: Command '{expanded_cmd}' failed with exit code {result.returncode}")
                    sys.exit(result.returncode)

def main():
    args = sys.argv[1:]
    taskfile = "Taskfile"
    target = None

    if len(args) >= 1:
        if os.path.exists(args[0]):
            taskfile = args[0]
            if len(args) >= 2:
                target = args[1]
        else:
            target = args[0]

    runner = TaskRunner()
    runner.parse_file(taskfile)
    runner.finalize_parsing()
    
    if target is None:
        target = runner.first_target
    
    if target is None:
        print(f"Error: No targets found in '{taskfile}'")
        sys.exit(1)
        
    if target not in runner.tasks and not os.path.exists(target):
        print(f"Error: Target '{target}' not found in '{taskfile}'")
        sys.exit(1)

    order = runner.resolve_dependencies(target)
    runner.execute(order)

if __name__ == "__main__":
    main()
