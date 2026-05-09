import * as fs from 'fs';
import * as path from 'path';
import { execSync } from 'child_process';

class Task {
    constructor(
        public name: string,
        public dependencies: string[] = [],
        public commands: string[] = []
    ) {}
}

class TaskRunner {
    tasks: Map<string, Task> = new Map();
    firstTarget: string | null = null;

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

            if (rawLine.startsWith('\t')) {
                if (currentTask) {
                    const command = line.trim();
                    if (command) {
                        this.tasks.get(currentTask)!.commands.push(command);
                    }
                }
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
                console.log(`Executing: ${cmd}`);
                try {
                    execSync(cmd, { stdio: 'inherit' });
                } catch (error) {
                    console.error(`Error: Command '${cmd}' failed`);
                    process.exit(1);
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
            if (args.length >= 2) {
                target = args[1];
            }
        } else {
            target = args[0];
        }
    }

    const runner = new TaskRunner();
    runner.parseFile(taskfile);

    if (target === null) {
        target = runner.firstTarget;
    }

    if (target === null) {
        console.error(`Error: No targets found in '${taskfile}'`);
        process.exit(1);
    }

    if (!runner.tasks.has(target) && !fs.existsSync(target)) {
        console.error(`Error: Target '${target}' not found in '${taskfile}'`);
        process.exit(1);
    }

    const order = runner.resolveDependencies(target);
    runner.execute(order);
}

if (require.main === module) {
    main();
}
