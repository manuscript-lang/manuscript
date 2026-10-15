const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PassThrough } = require('node:stream');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { Framing, ManuscriptAdapter } = require(process.env.MANUSCRIPT_DAP_ADAPTER || '../debug-adapter');

test('native DAP accessor body keeps source name and field inspection does not read it', { skip: !process.env.MANUSCRIPT_DAP_TEST, timeout: 60000 }, async () => {
  const source = `interface Counter:
    get next -> Int
type State:
    count: Int
impl Counter for State:
    get next -> Int:
        self.count = self.count + 1
        return self.count
export fn main() -> Int:
    let state = State(0)
    let observed = state.next
    return observed - state.count
`;
  const readLine = 11, bodyLine = 7, returnLine = 12;
  const directory = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'manuscript accessor dap ')));
  const program = path.join(directory, 'main.ms');
  await fs.writeFile(program, source);
  const output = new PassThrough();
  const messages = [], waiters = [];
  const adapter = new ManuscriptAdapter(output, { compiler: process.env.MANUSCRIPT_MS });
  const parser = new Framing(message => { messages.push(message); for (const wake of waiters.splice(0)) wake(); });
  output.on('data', bytes => parser.push(bytes));
  const wait = async predicate => {
    while (true) {
      const index = messages.findIndex(predicate);
      if (index >= 0) return messages.splice(index, 1)[0];
      await new Promise(resolve => waiters.push(resolve));
    }
  };
  let sequence = 1;
  const request = (command, args) => {
    const seq = sequence++;
    adapter.request({ seq, type: 'request', command, arguments: args });
    return seq;
  };
  const response = async seq => {
    const message = await wait(message => message.request_seq === seq);
    assert.equal(message.success, true, message.message);
    return message.body;
  };
  const stoppedFrame = async () => {
    const stopped = await wait(message => ['stopped', 'exited', 'terminated'].includes(message.event));
    assert.equal(stopped.event, 'stopped', 'program exited before the accessor breakpoint');
    const stack = await response(request('stackTrace', { threadId: stopped.body.threadId }));
    const frame = stack.stackFrames.find(frame => frame.source?.path === program);
    assert.ok(frame, JSON.stringify(stack));
    return { threadId: stopped.body.threadId, frame };
  };
  const inspectState = async (frame, count) => {
    const scopes = await response(request('scopes', { frameId: frame.id }));
    const locals = await response(request('variables', { variablesReference: scopes.scopes[0].variablesReference }));
    const state = locals.variables.find(variable => variable.name === 'state');
    assert.ok(state, JSON.stringify(locals));
    assert.equal(state.type, 'State');
    const fields = await response(request('variables', { variablesReference: state.variablesReference }));
    assert.deepEqual(fields.variables.map(variable => variable.name), ['count']);
    assert.equal(fields.variables[0].value, count);
    // A plain record watch also exposes stored data without invoking accessors.
    const watch = await response(request('evaluate', { frameId: frame.id, expression: 'state', context: 'watch' }));
    const watchedFields = await response(request('variables', { variablesReference: watch.variablesReference }));
    assert.deepEqual(watchedFields.variables.map(variable => variable.name), ['count']);
    assert.equal(watchedFields.variables[0].value, count);
    return locals;
  };
  try {
    await response(request('initialize', { adapterID: 'manuscript', linesStartAt1: true, columnsStartAt1: true, pathFormat: 'path', supportsVariableType: true }));
    const launch = request('launch', { program, stopOnEntry: false });
    const initialized = await wait(message => message.event === 'initialized' || (message.request_seq === launch && !message.success));
    assert.equal(initialized.event, 'initialized', initialized.message);
    const breakpoints = await response(request('setBreakpoints', { source: { path: program }, breakpoints: [{ line: readLine }, { line: bodyLine }, { line: returnLine }] }));
    assert.ok(breakpoints.breakpoints.every(point => point.verified), JSON.stringify(breakpoints));
    const configured = request('configurationDone');
    let stopped = await stoppedFrame();
    await response(configured); await response(launch);
    assert.equal(stopped.frame.name, 'main');
    assert.equal(stopped.frame.line, readLine);
    await inspectState(stopped.frame, '0');
    await response(request('continue', { threadId: stopped.threadId }));
    stopped = await stoppedFrame();
    assert.equal(stopped.frame.name, 'Counter for State.next');
    assert.equal(stopped.frame.line, bodyLine);
    await response(request('continue', { threadId: stopped.threadId }));
    stopped = await stoppedFrame();
    assert.equal(stopped.frame.name, 'main');
    assert.equal(stopped.frame.line, returnLine);
    const locals = await inspectState(stopped.frame, '1');
    assert.equal(locals.variables.find(variable => variable.name === 'observed').value, '1');
    await response(request('continue', { threadId: stopped.threadId }));
    const exited = await wait(message => message.event === 'exited' || message.event === 'terminated');
    if (exited.event === 'exited') assert.equal(exited.body.exitCode, 0);
  } finally {
    await adapter.cleanup();
    await fs.rm(directory, { recursive: true, force: true });
  }
});
