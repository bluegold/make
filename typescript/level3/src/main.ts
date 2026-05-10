import * as fs from 'fs';
import { spawn } from 'child_process';
import { expandVariables, normalizeProgram, parseTaskFile, Task } from '../../core';

class AsyncTaskRunner {
    executedTasks: Map<string, Promise<void>> = new Map();

    constructor(private readonly tasks: Map<string, Task>, private readonly variables: Map<string, string>) {}

    needsUpdate(target: string, dependencies: readonly string[]): boolean {
        if (!fs.existsSync(target)) return true;
        const targetStat = fs.statSync(target);
        return dependencies.some(dependency =>
            fs.existsSync(dependency) && fs.statSync(dependency).mtime > targetStat.mtime
        );
    }

    async executeTask(targetName: string): Promise<void> {
        const existing = this.executedTasks.get(targetName);
        if (existing) {
            return existing;
        }

        const promise = (async () => {
            const task = this.tasks.get(targetName);
            if (!task) {
                return;
            }

            await Promise.all(task.dependencies.map(dependency => this.executeTask(dependency)));

            if (!this.needsUpdate(targetName, task.dependencies)) return;

            const extraVars = new Map([
                ['$@', targetName],
                ['$<', task.dependencies[0] || ''],
                ['$^', task.dependencies.join(' ')],
            ]);

            await task.commands.reduce<Promise<void>>(async (chain, command) => {
                await chain;
                const expandedCommand = expandVariables(command, this.variables, {
                    extraVars,
                    allowSpecial: true,
                });
                const actualCommand = expandedCommand.startsWith('@')
                    ? expandedCommand.slice(1)
                    : expandedCommand;
                const silent = expandedCommand.startsWith('@');

                if (!silent) {
                    process.stdout.write(`Executing: ${actualCommand}\n`);
                }

                await new Promise<void>((resolve, reject) => {
                    const child = spawn('sh', ['-c', actualCommand], { stdio: 'inherit' });
                    child.on('close', code => {
                        if (code === 0) {
                            resolve();
                        } else {
                            reject(new Error(`Error: Command '${actualCommand}' failed with exit code ${code ?? 1}`));
                        }
                    });
                });
            }, Promise.resolve());
        })();

        this.executedTasks.set(targetName, promise);
        return promise;
    }
}

async function main() {
    const args = process.argv.slice(2);
    let taskfile = 'Taskfile';
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

    const program = normalizeProgram(parseTaskFile(taskfile));

    if (target === null) {
        target = program.firstTarget;
    }

    if (target === null) {
        throw new Error('Error: No targets found');
    }

    const checkCycle = (name: string, stack: Set<string> = new Set()) => {
        if (stack.has(name)) {
            throw new Error(`Error: Circular dependency detected involving '${name}'`);
        }

        const task = program.tasks.get(name);
        if (!task) {
            return;
        }

        stack.add(name);
        task.dependencies.forEach(dependency => checkCycle(dependency, stack));
        stack.delete(name);
    };

    checkCycle(target);

    const runner = new AsyncTaskRunner(program.tasks, program.variables);
    await runner.executeTask(target);
}

if (require.main === module) {
    main().catch(error => {
        console.error(error instanceof Error ? error.message : error);
        process.exit(1);
    });
}
