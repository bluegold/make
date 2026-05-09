import * as fs from 'fs';
import * as path from 'path';
import { spawn } from 'child_process';

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
    executedTasks: Map<string, Promise<void>> = new Map();

    expandVariables(text: string, extraVars: Map<string, string> = new Map(), expanding: string[] = []): string {
        // Handle special variables $@, $<, $^
        text = text.replace(/\$([@<^])/g, (match, char) => {
            return extraVars.get(`$${char}`) || match;
        });

        const pattern = /\$\(([^)]+)\)/g;
        return text.replace(pattern, (match, varName) => {
            if (expanding.includes(varName)) {
                const cycle = [...expanding, varName].join(' -> ');
                console.error(`Error: Circular variable reference detected: ${cycle}`);
                process.exit(1);
            }

            const val = extraVars.get(varName) || this.variables.get(varName) || process.env[varName] || "";
            expanding.push(varName);
            const result = this.expandVariables(val, extraVars, expanding);
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

            if (rawLine.startsWith('\t')) {
                if (currentTask) {
                    const command = line.trim();
                    if (command) {
                        this.tasks.get(currentTask)!.commands.push(command);
                    }
                }
                continue;
            }

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
                if (this.firstTarget === null) this.firstTarget = target;
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
        if (this.firstTarget) this.firstTarget = this.expandVariables(this.firstTarget);
    }

    needsUpdate(target: string, dependencies: string[]): boolean {
        if (!fs.existsSync(target)) return true;
        const targetStat = fs.statSync(target);
        for (const dep of dependencies) {
            if (fs.existsSync(dep)) {
                const depStat = fs.statSync(dep);
                if (depStat.mtime > targetStat.mtime) return true;
            }
        }
        return false;
    }

    async executeTask(targetName: string): Promise<void> {
        if (this.executedTasks.has(targetName)) {
            return this.executedTasks.get(targetName)!;
        }

        const promise = (async () => {
            const task = this.tasks.get(targetName);
            if (!task) {
                return;
            }

            // Run dependencies in parallel
            await Promise.all(task.dependencies.map(dep => this.executeTask(dep)));

            if (!this.needsUpdate(targetName, task.dependencies)) return;

            const extraVars = new Map([
                ['$@', targetName],
                ['$<', task.dependencies[0] || ''],
                ['$^', task.dependencies.join(' ')]
            ]);

            for (const cmd of task.commands) {
                const expandedCmd = this.expandVariables(cmd, extraVars);
                let silent = false;
                let actualCmd = expandedCmd;
                if (actualCmd.startsWith('@')) {
                    silent = true;
                    actualCmd = actualCmd.slice(1);
                }

                if (!silent) process.stdout.write(`Executing: ${actualCmd}\n`);
                try {
                    await new Promise<void>((resolve, reject) => {
                        const child = spawn('sh', ['-c', actualCmd], { stdio: 'inherit' });
                        child.on('close', (code) => {
                            if (code === 0) resolve();
                            else reject(Object.assign(new Error(`Exit ${code}`), { status: code }));
                        });
                    });
                } catch (error: any) {
                    process.exit(error.status || 1);
                }
            }
        })();

        this.executedTasks.set(targetName, promise);
        return promise;
    }
}

async function main() {
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

    // Check for circular dependencies
    const checkCycle = (t: string, stack: Set<string> = new Set()) => {
        if (stack.has(t)) {
            console.error(`Error: Circular dependency detected involving '${t}'`);
            process.exit(1);
        }
        const task = runner.tasks.get(t);
        if (!task) return;
        stack.add(t);
        for (const dep of task.dependencies) checkCycle(dep, stack);
        stack.delete(t);
    };
    checkCycle(target);

    await runner.executeTask(target);
}

if (require.main === module) {
    main().catch(err => {
        console.error(err);
        process.exit(1);
    });
}
