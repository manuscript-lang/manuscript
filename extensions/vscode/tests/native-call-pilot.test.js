// Run the prebuilt held pilot with MANUSCRIPT_NATIVE_CALL_FIXTURE and MANUSCRIPT_MS.
// The normal compiler/CLI does not enable this experimental calling convention.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PassThrough } = require('node:stream');
const path = require('node:path');
const { Framing, ManuscriptAdapter } = require(process.env.MANUSCRIPT_DAP_ADAPTER || '../debug-adapter');

test('held native-call pilot retains source frame, parameters, locals and watches', {
  skip: !process.env.MANUSCRIPT_NATIVE_CALL_FIXTURE, timeout: 60000
}, async () => {
  const directory = path.resolve(process.env.MANUSCRIPT_NATIVE_CALL_FIXTURE);
  const output = new PassThrough(); const messages = []; const waiters = [];
  const adapter = new ManuscriptAdapter(output, { compiler: process.env.MANUSCRIPT_MS });
  output.on('data', bytes => parser.push(bytes));
  const parser = new Framing(message => { messages.push(message); for (const wake of waiters.splice(0)) wake(); });
  const wait = async predicate => { while (true) { const index = messages.findIndex(predicate); if (index >= 0) return messages.splice(index, 1)[0]; await new Promise(resolve => waiters.push(resolve)); } };
  let sequence = 1;
  const request = (command, args) => { const seq = sequence++; adapter.request({ seq, type: 'request', command, arguments: args }); return seq; };
  const response = async seq => { const message = await wait(message => message.request_seq === seq); assert.equal(message.success, true, message.message); return message.body; };
  try {
    await response(request('initialize', { adapterID: 'manuscript', linesStartAt1: true, columnsStartAt1: true, pathFormat: 'path', supportsVariableType: true }));
    const launch = request('launch', { program: path.join(directory, 'program'), inspection: path.join(directory, 'inspection.json') });
    const initialized = await wait(message => message.event === 'initialized' || (message.request_seq === launch && !message.success));
    assert.equal(initialized.event, 'initialized', initialized.message);
    const source = path.join(directory, 'main.ms');
    const breakpoints = await response(request('setBreakpoints', { source: { path: source }, breakpoints: [{ line: 2 }] }));
    assert.equal(breakpoints.breakpoints[0].verified, true);
    const configured = request('configurationDone');
    const stopped = await wait(message => message.event === 'stopped');
    await response(configured); await response(launch);
    const before = await response(request('stackTrace', { threadId: stopped.body.threadId }));
    assert.equal(before.stackFrames[0].name, 'add'); assert.equal(before.stackFrames[0].line, 2);
    await response(request('next', { threadId: stopped.body.threadId }));
    const stepped = await wait(message => message.event === 'stopped');
    const stack = await response(request('stackTrace', { threadId: stepped.body.threadId }));
    const top = stack.stackFrames[0];
    assert.equal(top.name, 'add'); assert.equal(top.source.path, source); assert.equal(top.line, 3);
    const scopes = await response(request('scopes', { frameId: top.id }));
    const scope = scopes.scopes.find(item => item.name === 'Manuscript locals');
    assert.ok(scope, JSON.stringify(scopes));
    const locals = await response(request('variables', { variablesReference: scope.variablesReference }));
    for (const [name, value] of [['left', '1'], ['right', '2'], ['total', '3']]) {
      const variable = locals.variables.find(item => item.name === name);
      assert.ok(variable, JSON.stringify(locals)); assert.equal(variable.type, 'Int'); assert.equal(variable.value, value);
      const watch = await response(request('evaluate', { frameId: top.id, expression: name, context: 'watch' }));
      assert.equal(watch.result, value); assert.equal(watch.type, 'Int');
    }
    await response(request('disconnect', { terminateDebuggee: true }));
  } finally { await adapter.cleanup(); }
});
