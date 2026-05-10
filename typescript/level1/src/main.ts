import * as fs from 'fs';
import { parseTaskFile, resolveDependencies, runTaskOrder } from '../../core';

function main() {
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

    const program = parseTaskFile(taskfile);

    if (target === null) {
        target = program.firstTarget;
    }

    if (target === null) {
        throw new Error(`Error: No targets found in '${taskfile}'`);
    }

    if (!program.tasks.has(target) && !fs.existsSync(target)) {
        throw new Error(`Error: Target '${target}' not found in '${taskfile}'`);
    }

    const order = resolveDependencies(program.tasks, target);
    runTaskOrder(order, program.tasks);
}

if (require.main === module) {
    try {
        main();
    } catch (error: unknown) {
        console.error(error instanceof Error ? error.message : error);
        process.exit(1);
    }
}
