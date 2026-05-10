const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync, execFileSync } = require('child_process');

const rootDir = path.resolve(__dirname, '..');
const runner = path.join(rootDir, 'runner');
const builder = path.join(rootDir, 'builder');

function build() {
  execFileSync(builder, { stdio: 'inherit' });
}

function withTempDir(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-task-runner-'));
  try {
    return fn(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function writeTaskfile(dir, content) {
  const taskfile = path.join(dir, 'Taskfile');
  fs.writeFileSync(taskfile, content);
  return taskfile;
}

function taskfile(lines) {
  return `${lines.join('\n')}\n`;
}

function runRunner(level, taskfile, target, cwd, env = {}) {
  const command = [
    shellQuote(runner),
    level,
    shellQuote(taskfile),
    shellQuote(target),
  ].join(' ');

  return spawnSync('bash', ['-lc', command], {
    cwd,
    env: { ...process.env, ...env },
    encoding: 'utf8',
  });
}

function assertInOrder(text, items) {
  let cursor = 0;
  items.forEach(item => {
    const index = text.indexOf(item, cursor);
    expect(index).toBeGreaterThanOrEqual(cursor);
    cursor = index + item.length;
  });
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\"'\"'`)}'`;
}

beforeAll(() => {
  build();
});

test('level1 resolves dependencies in order', () => {
  withTempDir(dir => {
    const taskfilePath = writeTaskfile(dir, taskfile([
      'all: build prep',
      '\tprintf \'%s\\n\' all >> order.txt',
      '',
      'build:',
      '\tprintf \'%s\\n\' build >> order.txt',
      '',
      'prep:',
      '\tprintf \'%s\\n\' prep >> order.txt',
    ]));

    const result = runRunner('level1', taskfilePath, 'all', dir);

    expect(result.status).toBe(0);
    const lines = fs.readFileSync(path.join(dir, 'order.txt'), 'utf8').trim().split('\n');
    expect(lines).toEqual(['build', 'prep', 'all']);
  });
});

test('level2 expands variables before execution', () => {
  withTempDir(dir => {
    const taskfilePath = writeTaskfile(dir, taskfile([
      'NAME = world',
      '',
      'greet:',
      '\tprintf \'%s\\n\' "Hello $(NAME)" > greeting.txt',
    ]));

    const result = runRunner('level2', taskfilePath, 'greet', dir);

    expect(result.status).toBe(0);
    expect(fs.readFileSync(path.join(dir, 'greeting.txt'), 'utf8').trim()).toBe('Hello world');
  });
});

test('level3 supports automatic variables and timestamp skipping', () => {
  withTempDir(dir => {
    const taskfilePath = writeTaskfile(dir, taskfile([
      'output.txt: input.txt dep2.txt',
      '\tprintf \'%s\\n\' "$@ from $< and $^" >> run.log',
      '\ttouch $@',
    ]));

    fs.writeFileSync(path.join(dir, 'input.txt'), 'input');
    fs.writeFileSync(path.join(dir, 'dep2.txt'), 'dep2');

    const first = runRunner('level3', taskfilePath, 'output.txt', dir);
    expect(first.status).toBe(0);
    expect(fs.readFileSync(path.join(dir, 'run.log'), 'utf8').trim()).toBe('output.txt from input.txt and input.txt dep2.txt');

    const second = runRunner('level3', taskfilePath, 'output.txt', dir);
    expect(second.status).toBe(0);
    expect(fs.readFileSync(path.join(dir, 'run.log'), 'utf8').trim()).toBe('output.txt from input.txt and input.txt dep2.txt');
    expect(fs.existsSync(path.join(dir, 'output.txt'))).toBe(true);
  });
});
