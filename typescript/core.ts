import * as fs from 'fs';
import { spawnSync } from 'child_process';

export class Task {
    constructor(
        public readonly name: string,
        public readonly dependencies: readonly string[] = [],
        public readonly commands: readonly string[] = []
    ) {}
}

type MutableTask = {
    name: string;
    dependencies: string[];
    commands: string[];
};

export type ParsedProgram = Readonly<{
    tasks: Map<string, Task>;
    variables: Map<string, string>;
    firstTarget: string | null;
}>;

export type ExpandOptions = Readonly<{
    extraVars?: Map<string, string>;
    allowSpecial?: boolean;
    expanding?: Set<string>;
}>;

export function parseTaskFile(filepath: string): ParsedProgram {
    if (!fs.existsSync(filepath)) {
        throw new Error(`Error: File '${filepath}' not found.`);
    }

    const content = fs.readFileSync(filepath, 'utf-8');
    const tasks = new Map<string, MutableTask>();
    const variables = new Map<string, string>();
    let firstTarget: string | null = null;
    let currentTask: string | null = null;

    content.split('\n').forEach(originalLine => {
        let line = originalLine;
        const rawLine = line;
        line = line.trimEnd();
        if (!line || line.trimStart().startsWith('#')) return;

        if (rawLine.length > 0 && (rawLine[0] === '\t' || rawLine[0] === ' ')) {
            if (currentTask) {
                const command = line.trim();
                if (command) {
                    tasks.get(currentTask)!.commands.push(command);
                }
            }
            return;
        }

        if (line.includes('=') && (!line.includes(':') || line.indexOf('=') < line.indexOf(':'))) {
            const parts = line.split('=');
            const key = parts[0].trim();
            const value = parts.slice(1).join('=').trim();
            variables.set(key, value);
            currentTask = null;
            return;
        }

        if (line.includes(':')) {
            const [targetPart, depsPart] = line.split(':');
            const target = targetPart.trim();
            const deps = (depsPart || '').split(/\s+/).map(d => d.trim()).filter(d => d.length > 0);

            tasks.set(target, { name: target, dependencies: deps, commands: [] });
            if (firstTarget === null) {
                firstTarget = target;
            }
            currentTask = target;
        }
    });

    return {
        tasks: new Map(
            Array.from(tasks.entries()).map(([name, task]) => [
                name,
                new Task(task.name, [...task.dependencies], [...task.commands]),
            ] as const)
        ),
        variables,
        firstTarget,
    };
}

export function normalizeProgram(program: ParsedProgram): ParsedProgram {
    const firstTarget = program.firstTarget;
    const tasks = new Map(
        Array.from(program.tasks.entries()).map(([name, task]) => {
            const expandedName = expandVariables(name, program.variables);
            const expandedDeps = task.dependencies.flatMap(dependency =>
                expandVariables(dependency, program.variables).split(/\s+/).filter(Boolean)
            );
            return [
                expandedName,
                new Task(expandedName, expandedDeps, [...task.commands]),
            ] as const;
        })
    );

    return {
        tasks,
        variables: new Map(Array.from(program.variables.entries())),
        firstTarget: firstTarget ? expandVariables(firstTarget, program.variables) : null,
    };
}

export function expandVariables(text: string, variables: Map<string, string>, options: ExpandOptions = {}): string {
    const extraVars = options.extraVars ?? new Map<string, string>();
    const allowSpecial = options.allowSpecial ?? false;
    const expanding = options.expanding ?? new Set<string>();

    const expandedSpecial = text.replace(/\$([@<^])/g, (match, char) => {
        const key = `$${char}`;
        if (extraVars.has(key)) {
            return extraVars.get(key) ?? '';
        }
        if (allowSpecial) {
            return match;
        }
        throw new Error(`Error: Special variable '${key}' is not supported.`);
    });

    return expandedSpecial.replace(/\$\(([^)]+)\)/g, (_, varName: string) => {
        if (expanding.has(varName)) {
            const cycle = [...expanding, varName].join(' -> ');
            throw new Error(`Error: Circular variable reference detected: ${cycle}`);
        }

        const rawValue = extraVars.get(varName) ?? process.env[varName] ?? variables.get(varName) ?? '';
        const nextExpanding = new Set(expanding);
        nextExpanding.add(varName);
        return expandVariables(rawValue, variables, {
            extraVars,
            allowSpecial,
            expanding: nextExpanding,
        });
    });
}

export function resolveDependencies(tasks: Map<string, Task>, target: string): string[] {
    const visited = new Set<string>();
    const stack = new Set<string>();

    const visit = (name: string): string[] => {
        if (stack.has(name)) {
            throw new Error(`Error: Circular dependency detected involving '${name}'`);
        }

        if (visited.has(name)) {
            return [];
        }

        if (!tasks.has(name)) {
            if (fs.existsSync(name)) {
                visited.add(name);
                return [];
            }
            throw new Error(`Error: No rule to make target '${name}'`);
        }

        stack.add(name);
        const task = tasks.get(name)!;
        const order = task.dependencies.reduce<string[]>(
            (acc, dependency) => acc.concat(visit(dependency)),
            []
        );
        stack.delete(name);
        visited.add(name);
        return [...order, name];
    };

    return visit(target);
}

export function runTaskOrder(
    order: readonly string[],
    tasks: Map<string, Task>,
    expandCommand: (command: string, task: Task) => string = command => command
): void {
    order.forEach(targetName => {
        const task = tasks.get(targetName);
        if (!task) return;

        task.commands.forEach(command => {
            const expandedCommand = expandCommand(command, task);
            console.log(`Executing: ${expandedCommand}`);
            const result = spawnSync('sh', ['-c', expandedCommand], { stdio: 'pipe' });
            if (result.stdout) process.stdout.write(result.stdout);
            if (result.stderr) process.stderr.write(result.stderr);
            if (result.status !== 0) {
                throw new Error(`Error: Command '${expandedCommand}' failed`);
            }
        });
    });
}
