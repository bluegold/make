import sys
import os
import subprocess
import re
import time
from concurrent.futures import ThreadPoolExecutor

class Task:
    def __init__(self, name, dependencies=None, commands=None):
        self.name = name
        self.dependencies = dependencies or []
        self.commands = commands or []

class TaskRunner:
    def __init__(self):
        self.tasks = {}
        self.variables = {}
        self.first_target = None
        self.futures = {}
        self.executor = None

    def expand_variables(self, text, extra_vars=None, expanding=None):
        if expanding is None:
            expanding = []
        if extra_vars is None:
            extra_vars = {}
        
        def replace_special(match):
            var = match.group(0)
            return str(extra_vars.get(var, var))
        
        text = re.sub(r'\$[@<^]', replace_special, text)

        pattern = r'\$\(([^)]+)\)'
        def replace_normal(match):
            var_name = match.group(1)
            if var_name in expanding:
                cycle = " -> ".join(expanding + [var_name])
                print(f"Error: Circular variable reference detected: {cycle}")
                sys.exit(1)
            
            val = extra_vars.get(var_name, os.environ.get(var_name, self.variables.get(var_name, "")))
            
            expanding.append(var_name)
            result = self.expand_variables(val, extra_vars, expanding)
            expanding.pop()
            return result
        
        return re.sub(pattern, replace_normal, text)

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

                if '=' in line and (':' not in line or line.find('=') < line.find(':')):
                    parts = line.split('=', 1)
                    key = parts[0].strip()
                    value = parts[1].strip()
                    self.variables[key] = value
                    current_task = None
                    continue

                if ':' in line:
                    parts = line.split(':')
                    target = parts[0].strip()
                    deps = [d.strip() for d in parts[1].split() if d.strip()]
                    self.tasks[target] = Task(target, deps)
                    if self.first_target is None:
                        self.first_target = target
                    current_task = target

    def finalize_parsing(self):
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

    def needs_update(self, target, dependencies):
        if not os.path.exists(target):
            return True
        
        target_mtime = os.path.getmtime(target)
        for dep in dependencies:
            if os.path.exists(dep):
                if os.path.getmtime(dep) > target_mtime:
                    return True
        return False

    def execute_task(self, target_name):
        if target_name in self.futures:
            return self.futures[target_name]
        
        task = self.tasks.get(target_name)
        
        if not task:
            # File dependency
            def noop():
                if not os.path.exists(target_name):
                    # This will be caught when the dependent task runs its needs_update
                    pass
            f = self.executor.submit(noop)
            self.futures[target_name] = f
            return f

        # Submit all dependencies
        dep_futures = [self.execute_task(d) for d in task.dependencies]

        def run_task():
            # 1. Wait for all dependencies to finish
            for df in dep_futures:
                df.result()
            
            # 2. Check if we need to run
            if not self.needs_update(target_name, task.dependencies):
                return

            # 3. Run commands
            extra_vars = {
                '$@': target_name,
                '$<': task.dependencies[0] if task.dependencies else "",
                '$^': " ".join(task.dependencies)
            }

            for cmd in task.commands:
                expanded_cmd = self.expand_variables(cmd, extra_vars)
                silent = False
                actual_cmd = expanded_cmd
                if actual_cmd.startswith('@'):
                    silent = True
                    actual_cmd = actual_cmd[1:]

                if not silent:
                    # Use a lock or print atomic to avoid mangled output in parallel
                    # For simplicity in this challenge, we just print
                    print(f"Executing: {actual_cmd}")
                    sys.stdout.flush()
                
                result = subprocess.run(actual_cmd, shell=True)
                if result.returncode != 0:
                    print(f"Error: Command '{actual_cmd}' failed with exit code {result.returncode}")
                    # We can't easily stop all threads, but we can exit the main process
                    os._exit(result.returncode)

        f = self.executor.submit(run_task)
        self.futures[target_name] = f
        return f

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
        
    def check_cycle(t, stack):
        if t in stack:
            print(f"Error: Circular dependency detected involving '{t}'")
            sys.exit(1)
        if t not in runner.tasks:
            return
        stack.add(t)
        for d in runner.tasks[t].dependencies:
            check_cycle(d, stack)
        stack.remove(t)
    
    check_cycle(target, set())

    # Use a thread pool for parallel execution
    # Number of workers could be an argument, but let's default to a reasonable number
    with ThreadPoolExecutor(max_workers=4) as executor:
        runner.executor = executor
        final_future = runner.execute_task(target)
        final_future.result()

if __name__ == "__main__":
    main()
