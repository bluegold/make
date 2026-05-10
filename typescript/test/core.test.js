const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const rootDir = path.resolve(__dirname, '..');
const builder = path.join(rootDir, 'builder');

function build() {
  execFileSync(builder, { stdio: 'inherit' });
}

function withTempDir(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-task-core-'));
  try {
    return fn(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

beforeAll(() => {
  build();
});

test('core parser and resolver work together', () => {
  withTempDir(dir => {
    const taskfile = path.join(dir, 'Taskfile');
    fs.writeFileSync(taskfile, [
      'all: build prep',
      '\techo all',
      '',
      'build:',
      '\techo build',
      '',
      'prep:',
      '\techo prep',
    ].join('\n') + '\n');

    const core = require('../dist/core');
    const program = core.parseTaskFile(taskfile);
    const order = core.resolveDependencies(program.tasks, 'all');

    expect(program.firstTarget).toBe('all');
    expect(order).toEqual(['build', 'prep', 'all']);
  });
});

test('core normalizer expands variables', () => {
  withTempDir(dir => {
    const taskfile = path.join(dir, 'Taskfile');
    fs.writeFileSync(taskfile, [
      'NAME = app',
      '',
      '$(NAME): $(DEPS)',
      '\techo link',
    ].join('\n') + '\n');

    const core = require('../dist/core');
    const program = core.normalizeProgram(core.parseTaskFile(taskfile));

    expect(program.firstTarget).toBe('app');
    expect(program.tasks.has('app')).toBe(true);
  });
});
