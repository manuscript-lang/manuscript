const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PassThrough } = require('node:stream');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { Framing, ManuscriptAdapter } = require(process.env.MANUSCRIPT_DAP_ADAPTER || '../debug-adapter');

const declarations = `interface Read:
    fn read() -> Int
type Reader:
    operation: fn() -> Int
impl Read for Reader:
    fn read() -> Int:
        return self.operation()
export fn main() -> Int:
`;

for (const [name, body, breakpointLine, anonymousFrames] of [
  ['exact reproduction', '    let view = Read(Reader(fn() -> Int: 1))\n    return view.read()\n', 9, 1],
  ['nested capture', `    var value = 7
    let view = Read(Reader(fn() -> Int:
        let nested = fn() -> Int:
            return value
        return nested()
    ))
    value = 90
    return view.read() - 7
`, 12, 2],
]) {
  test(`native DAP interface view ${name}`, { skip: !process.env.MANUSCRIPT_DAP_TEST, timeout: 60000 }, async () => {
    const directory = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'manuscript view dap ')));
    const program = path.join(directory, 'main.ms');
    await fs.writeFile(program, declarations + body);
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
      const breakpoints = await response(request('setBreakpoints', { source: { path: program }, breakpoints: [{ line: breakpointLine }] }));
      assert.equal(breakpoints.breakpoints[0].verified, true);
      const configured = request('configurationDone');
      let stopped = await stop();
      await response(configured); await response(launch);
      let stack;
      // The exact inline callback shares its source line with construction.
      // Continue past that main-frame stop to the callback's actual execution.
      for (let attempt = 0; attempt < 6; attempt++) {
        stack = await response(request('stackTrace', { threadId: stopped.body.threadId }));
        const sourceFrames = stack.stackFrames.filter(item => item.source?.path === program);
        if (sourceFrames.findIndex(item => item.name.endsWith('.read')) === anonymousFrames) break;
        await response(request('continue', { threadId: stopped.body.threadId }));
        stopped = await stop();
      }
      const frames = stack.stackFrames.filter(item => item.source?.path?.endsWith('.ms'));
      assert.equal(frames[0].line, breakpointLine);
      // The adapter names callable frames after their enclosing declaration.
      // Their source frames must still precede the implementation and caller.
      assert.equal(frames.findIndex(item => item.name.endsWith('.read')), anonymousFrames);
      assert.ok(frames.some(item => item.name.endsWith('.read') && item.line === 7));
      assert.ok(frames.some(item => item.name === 'main'));
      for (const item of frames) {
        assert.equal(item.source.path, program);
        assert.ok(item.line >= 1 && item.line <= (declarations + body).split('\n').length);
      }
      await response(request('continue', { threadId: stopped.body.threadId }));
      await wait(message => message.event === 'terminated');
    } finally {
      await adapter.cleanup();
      await fs.rm(directory, { recursive: true, force: true });
    }
  });
}
