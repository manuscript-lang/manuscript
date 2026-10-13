const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PassThrough } = require('node:stream');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { Framing, ManuscriptAdapter } = require(process.env.MANUSCRIPT_DAP_ADAPTER || '../debug-adapter');

test('native scalar calls retain parameters locals watches and source stepping', { skip: !process.env.MANUSCRIPT_DAP_TEST, timeout: 60000 }, async () => {
    const directory = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'manuscript scalar dap ')));
    const program = path.join(directory, 'main.ms');
    await fs.writeFile(program, `fn step(left: Int, right: Int) -> Int:
    var total = left + right
    total = total + 1
    return total
export fn main() -> Int:
    let seed = 1000
    var value = 0
    value = step(seed, 7)
    return value - 1008
`);
    const output = new PassThrough();
    const messages = []; const waiters = [];
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
    const stop = async () => {
      const message = await wait(message => ['stopped', 'exited', 'terminated'].includes(message.event));
      assert.equal(message.event, 'stopped', 'program exited before the callable breakpoint');
      return message;
    };
    try {
      await response(request('initialize', { adapterID: 'manuscript', linesStartAt1: true, columnsStartAt1: true, pathFormat: 'path' }));
      const launch = request('launch', { program, stopOnEntry: false });
      const initialized = await wait(message => message.event === 'initialized' || (message.request_seq === launch && !message.success));
      assert.equal(initialized.event, 'initialized', initialized.message);
      const points = await response(request('setBreakpoints', { source: { path: program }, breakpoints: [{ line: 3 }, { line: 9 }] }));
      assert.ok(points.breakpoints.every(point => point.verified), JSON.stringify(points));
      assert.equal(points.breakpoints[0].line, 3, JSON.stringify(points));
      const configured = request('configurationDone');
      let stopped = await stop(); await response(configured); await response(launch);
      let stack = await response(request('stackTrace', { threadId: stopped.body.threadId }));
      assert.equal(stack.stackFrames[0].name, 'step', JSON.stringify(stack));
      assert.equal(stack.stackFrames[0].line, 3);
      await response(request('next', { threadId: stopped.body.threadId }));
      stopped = await stop(); stack = await response(request('stackTrace', { threadId: stopped.body.threadId }));
      const frame = stack.stackFrames[0];
      assert.equal(frame.name, 'step', JSON.stringify(stack)); assert.equal(frame.line, 4); assert.equal(frame.source.path, program);
      const scopes = await response(request('scopes', { frameId: frame.id }));
      const locals = await response(request('variables', { variablesReference: scopes.scopes[0].variablesReference }));
      for (const [name,value] of [['left','1000'],['right','7'],['total','1008']]) {
        const local = locals.variables.find(local => local.name === name);
        assert.ok(local, JSON.stringify(locals)); assert.equal(local.value, value); assert.equal(local.type, 'Int');
        const watch = await response(request('evaluate', { frameId: frame.id, expression: name, context: 'watch' }));
        assert.equal(watch.result, value);
      }
      await response(request('continue', { threadId: stopped.body.threadId }));
      stopped = await stop(); stack = await response(request('stackTrace', { threadId: stopped.body.threadId }));
      assert.equal(stack.stackFrames[0].name, 'main'); assert.equal(stack.stackFrames[0].line, 9);
      const mainWatch = await response(request('evaluate', { frameId: stack.stackFrames[0].id, expression: 'value', context: 'watch' }));
      assert.equal(mainWatch.result, '1008');
      await response(request('continue', { threadId: stopped.body.threadId }));
      await wait(message => message.event === 'terminated' || message.event === 'exited');
    } finally { await adapter.cleanup(); await fs.rm(directory, { recursive: true, force: true }); }
});
