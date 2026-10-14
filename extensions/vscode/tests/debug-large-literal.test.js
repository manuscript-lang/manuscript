const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { PassThrough } = require('node:stream');
const { Framing, ManuscriptAdapter } = require(process.env.MANUSCRIPT_DAP_ADAPTER || '../debug-adapter');

test('Debug large scalar literal keeps source steps, locals, watches and fresh storage', { skip: !process.env.MANUSCRIPT_DAP_TEST, timeout: 90000 }, async () => {
  const directory = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'manuscript large literal dap ')));
  const program = path.join(directory, 'main.ms');
  const literal = Array(1100).fill('7').join(', ');
  const source = `\nexport fn main() -> Int:\n    let items = [${literal}]\n\n\n    let again = [${literal}]\n\n\n    items.with_value(index: 0, value: 99)\n\n\n    return again.at(0).unwrap() - 7\n`;
  const returnLine = 12;
  await fs.writeFile(program, source);
  const output = new PassThrough(); const messages = []; const waiters = [];
  const adapter = new ManuscriptAdapter(output, { compiler: process.env.MANUSCRIPT_MS });
  const parser = new Framing(message => { messages.push(message); for (const wake of waiters.splice(0)) wake(); });
  output.on('data', bytes => parser.push(bytes));
  const wait = async predicate => { while (true) { const index = messages.findIndex(predicate); if (index >= 0) return messages.splice(index, 1)[0]; await new Promise(resolve => waiters.push(resolve)); } };
  let sequence = 1;
  const request = (command, args) => { const seq = sequence++; adapter.request({ seq, type: 'request', command, arguments: args }); return seq; };
  const response = async seq => { const message = await wait(message => message.request_seq === seq); assert.equal(message.success, true, message.message); return message.body; };
  const top = async threadId => { const frames = await response(request('stackTrace', { threadId })); return frames.stackFrames.find(frame => frame.source && path.resolve(frame.source.path) === program); };
  try {
    await response(request('initialize', { adapterID: 'manuscript', linesStartAt1: true, columnsStartAt1: true, pathFormat: 'path', supportsVariableType: true }));
    const launch = request('launch', { program, stopOnEntry: false });
    const initialized = await wait(message => message.event === 'initialized' || (message.request_seq === launch && !message.success));
    assert.equal(initialized.event, 'initialized', initialized.message);
    const points = await response(request('setBreakpoints', { source: { path: program }, breakpoints: [{ line: 3 }, { line: returnLine }] }));
    assert.ok(points.breakpoints.every(point => point.verified), JSON.stringify(points));
    await response(request('configurationDone', {}));
    let stopped = await wait(message => message.event === 'stopped');
    let threadId = stopped.body.threadId;
    assert.equal((await top(threadId)).line, 3);
    await response(request('next', { threadId }));
    stopped = await wait(message => message.event === 'stopped'); threadId = stopped.body.threadId;
    const stepped = await top(threadId);
    // Delve can coalesce the next declaration with following bookkeeping;
    // require a source-level stop after construction, never a generated thunk.
    assert.ok(stepped.line > 3 && stepped.line <= 6, JSON.stringify(stepped));
    await response(request('continue', { threadId }));
    stopped = await wait(message => message.event === 'stopped'); threadId = stopped.body.threadId;
    const frame = await top(threadId); assert.equal(frame.line, returnLine);
    const scopes = await response(request('scopes', { frameId: frame.id }));
    const locals = await response(request('variables', { variablesReference: scopes.scopes[0].variablesReference }));
    for (const name of ['items', 'again']) {
      const value = locals.variables.find(variable => variable.name === name);
      assert.ok(value, JSON.stringify({ frame, scopes, locals })); assert.equal(value.type, 'List[Int]');
      const entries = await response(request('variables', { variablesReference: value.variablesReference }));
      assert.ok(entries.variables.length > 0);
      assert.equal(entries.variables[0].value, name === 'items' ? '99' : '7');
    }
    const watch = await response(request('evaluate', { frameId: frame.id, expression: 'again', context: 'watch' }));
    assert.equal(watch.type, 'List[Int]');
    await response(request('continue', { threadId }));
    await wait(message => message.event === 'terminated' || message.event === 'exited');
  } finally { await adapter.cleanup(); await fs.rm(directory, { recursive: true, force: true }); }
});
