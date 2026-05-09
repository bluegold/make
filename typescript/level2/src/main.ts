import * as fs from 'fs';
import { spawnSync } from 'child_process';

class Task {
    constructor(
        public name: string,
        public dependencies: string[] = [],
        public commands: string[] = []
    ) {}
}

class TaskRunner {
    tasks: Map<string, Task> = new Map();
    variables: Map<string, string> = new Map();
    firstTarget: string | null = null;

    expandVariables(text: string, expanding: string[] = []): string {
        const pattern = /\$\(([^)]+)\)/g;
        return text.replace(pattern, (match, varName) => {
            if (expanding.includes(varName)) {
                const cycle = [...expanding, varName].join(' -> ');
                console.error(`Error: Circular variable reference detected: ${cycle}`);
                process.exit(1);
            }

            const val = process.env[varName] || this.variables.get(varName) || "";
            expanding.push(varName);
            const result = this.expandVariables(val, expanding);
            expanding.pop();
            return result;
        });
    }

    parseFile(filepath: string) {
        if (!fs.existsSync(filepath)) {
            console.error(`Error: File '${filepath}' not found.`);
            process.exit(1);
        }

        const content = fs.readFileSync(filepath, 'utf-8');
        let currentTask: string | null = null;

        for (let line of content.split('\n')) {
            const rawLine = line;
            line = line.trimEnd();
            if (!line || line.trimStart().startsWith('#')) continue;

            if (rawLine.length > 0 && (rawLine[0] === '\t' || rawLine[0] === ' ')) {
                if (currentTask) {
                    const command = line.trim();
                    if (command) {
                        this.tasks.get(currentTask)!.commands.push(command);
                    }
                }
                continue;
            }

            // Variable definition
            if (line.includes('=') && (!line.includes(':') || line.indexOf('=') < line.indexOf(':'))) {
                const parts = line.split('=');
                const key = parts[0].trim();
                const value = parts.slice(1).join('=').trim();
                this.variables.set(key, value);
                currentTask = null;
                continue;
            }

            if (line.includes(':')) {
                const [targetPart, depsPart] = line.split(':');
                const target = targetPart.trim();
                const deps = (depsPart || '').split(/\s+/).map(d => d.trim()).filter(d => d.length > 0);

                this.tasks.set(target, new Task(target, deps));
                if (this.firstTarget === null) {
                    this.firstTarget = target;
                }
                currentTask = target;
            }
        }
    }

    finalizeParsing() {
        const finalTasks: Map<string, Task> = new Map();
        for (const [name, task] of this.tasks.entries()) {
            const expandedName = this.expandVariables(name);
            const expandedDeps: string[] = [];
            for (const d of task.dependencies) {
                const expandedVal = this.expandVariables(d);
                expandedDeps.push(...expandedVal.split(/\s+/).filter(s => s.length > 0));
            }
            task.name = expandedName;
            task.dependencies = expandedDeps;
            finalTasks.set(expandedName, task);
        }
        this.tasks = finalTasks;
        if (this.firstTarget) {
            this.firstTarget = this.expandVariables(this.firstTarget);
        }
    }

    resolveDependencies(target: string, visited: Set<string> = new Set(), stack: Set<string> = new Set()): string[] {
        if (stack.has(target)) {
            console.error(`Error: Circular dependency detected involving '${target}'`);
            process.exit(1);
        }
        if (visited.has(target)) return [];

        if (!this.tasks.has(target)) {
            if (fs.existsSync(target)) {
                visited.add(target);
                return [];
            } else {
                console.error(`Error: No rule to make target '${target}'`);
                process.exit(1);
            }
        }

        stack.add(target);
        let order: string[] = [];
        const task = this.tasks.get(target)!;
        for (const dep of task.dependencies) {
            order = order.concat(this.resolveDependencies(dep, visited, stack));
        }
        stack.delete(target);
        visited.add(target);
        order.push(target);
        return order;
    }

    execute(targetOrder: string[]) {
        for (const targetName of targetOrder) {
            const task = this.tasks.get(targetName);
            if (!task) continue;

            for (const cmd of task.commands) {
                const expandedCmd = this.expandVariables(cmd);
                console.log(`Executing: ${expandedCmd}`);
                const result = spawnSync('sh', ['-c', expandedCmd], { stdio: 'pipe' });
                if (result.stdout) process.stdout.write(result.stdout);
                if (result.stderr) process.stderr.write(result.stderr);
                if (result.status !== 0) {
                    process.exit(result.status || 1);
                }
            }
        }
    }
}

function main() {
    const args = process.argv.slice(2);
    let taskfile = "Taskfile";
    let target: string | null = null;

    if (args.length >= 1) {
        if (fs.existsSync(args[0])) {
            taskfile = args[0];
            if (args.length >= 2) target = args[1];
        } else {
            target = args[0];
        }
    }

    const runner = new TaskRunner();
    runner.parseFile(taskfile);
    runner.finalizeParsing();

    if (target === null) target = runner.firstTarget;
    if (target === null) {
        console.error("Error: No targets found");
        process.exit(1);
    }

    const order = runner.resolveDependencies(target);
    runner.execute(order);
}

if (require.main === module) {
    main();
}
