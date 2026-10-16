const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PassThrough } = require('node:stream');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { Framing, frame, ManuscriptAdapter, sourceType, mapName, rewriteExpression, goField, sourceField, typeArguments } = require(process.env.MANUSCRIPT_DAP_ADAPTER || '../debug-adapter');
require('./interface-view-debug.test');

test('DAP framing preserves fragmented UTF-8 and multiple messages', () => {
  const messages = []; const parser = new Framing(message => messages.push(message));
  const packet = Buffer.concat([frame({ seq: 1, text: '😀é' }), frame({ seq: 2 })]);
  for (const byte of packet) parser.push(Buffer.from([byte]));
  assert.deepEqual(messages, [{ seq: 1, text: '😀é' }, { seq: 2 }]);
  assert.throws(() => new Framing(() => {}).push(Buffer.from('Content-Length: 999999999\r\n\r\n')));
});
test('Manuscript values use source names and lazy structured handles', async () => {
  const adapter = new ManuscriptAdapter(new PassThrough());
  assert.equal(sourceType('int'), 'Int');
  assert.equal(sourceType('*github.com/manuscript-lang/manuscript/pkg/runtime.Map[string,int]'), 'Map[String,Int]');
  assert.equal(sourceType('*runtime.List[main.Box]'), 'List[Box]');
  assert.equal(sourceType('runtime.Option[float64]'), 'Optional[Float]');
  assert.equal(mapName('["name"]'), 'name');
  const box = adapter.render({ name: 'box', type: '*main.Box', value: '*main.Box {Label: "x", Count: 42}', variablesReference: 5 }, 'box', 'Box');
  assert.equal(box.name, 'box'); assert.equal(box.value, 'Box'); assert.equal(box.type, 'Box');
  const children = new Map([[5, [{ name: '', variablesReference: 6 }]], [6, [{ name: 'Label', type: 'string', value: '"x"' }, { name: 'FirstName', type: 'int', value: '42' }]]]);
  adapter.children = async ref => children.get(ref);
  const fields = await adapter.valueChildren(adapter.handles.get(box.variablesReference), {});
  assert.deepEqual(fields.map(field => [field.name, field.value, field.type]), [['label', '"x"', 'String'], ['first_name', '42', 'Int']]);
});

test('record fields map between Go and source names', () => {
  assert.equal(goField('first_name'), 'FirstName');
  assert.equal(goField('x'), 'X');
  assert.equal(sourceField('FirstName'), 'first_name');
  assert.equal(sourceField('Count'), 'count');
  assert.deepEqual(typeArguments('Map[String, List[Int]]'), ['String', 'List[Int]']);
  assert.deepEqual(typeArguments('Result[fn(Int, Int) -> Int, Failure]'), ['fn(Int, Int) -> Int', 'Failure']);
  assert.deepEqual(typeArguments('Box'), []);
});

test('options, results, lists and maps render as source values', async () => {
  const adapter = new ManuscriptAdapter(new PassThrough());
  const tree = new Map([
    [1, [{ name: 'Val', type: 'int', value: '5' }, { name: 'Some', type: 'bool', value: 'true' }]],
    [2, [{ name: 'Items', type: '[]int', value: '[]int len: 2', variablesReference: 3 }]],
    [3, [{ name: '[0]', type: 'int', value: '7' }, { name: '[1]', type: 'int', value: '8' }]],
    [4, [{ name: 'Val', type: 'int', value: '0' }, { name: 'Err', type: 'string', value: '"bad"' }, { name: 'Failed', type: 'bool', value: 'true' }]],
    [5, [{ name: 'entries', type: '[]*runtime.MapEntry[string,int]', variablesReference: 6 }]],
    [6, [{ name: '[0]', variablesReference: 7 }, { name: '[1]', value: 'nil', variablesReference: 0 }]],
    [7, [{ name: '', variablesReference: 8 }]],
    [8, [{ name: 'Key', type: 'string', value: '"k"' }, { name: 'Value', type: 'int', value: '1' }]],
  ]);
  adapter.children = async ref => tree.get(ref) || [];
  const option = adapter.render({ name: 'o', type: 'runtime.Option[int]', value: '{Val: 5, Some: true}', variablesReference: 1 }, 'o', 'Optional[Int]');
  assert.equal(option.value, 'some');
  assert.deepEqual((await adapter.valueChildren(adapter.handles.get(option.variablesReference), {})).map(v => [v.name, v.value, v.type]), [['value', '5', 'Int']]);
  const none = adapter.render({ name: 'o', type: 'runtime.Option[int]', value: '{Val: 0, Some: false}', variablesReference: 1 }, 'o', 'Optional[Int]');
  assert.equal(none.value, 'none'); assert.equal(none.variablesReference, 0);
  const list = adapter.render({ name: 'l', type: '*runtime.List[int]', value: '*runtime.List[int] {Items: []int len: 2, cap: 2, [7,8]}', variablesReference: 2 }, 'l', 'List[Int]');
  assert.equal(list.value, 'List[Int] (2 items)');
  assert.deepEqual((await adapter.valueChildren(adapter.handles.get(list.variablesReference), {})).map(v => [v.name, v.value, v.type]), [['[0]', '7', 'Int'], ['[1]', '8', 'Int']]);
  const result = adapter.render({ name: 'r', type: 'runtime.Result[int,string]', value: '{Val: 0, Err: "bad", Failed: true}', variablesReference: 4 }, 'r', 'Result[Int, String]');
  assert.equal(result.value, 'failed');
  assert.deepEqual((await adapter.valueChildren(adapter.handles.get(result.variablesReference), {})).map(v => [v.name, v.value, v.type]), [['error', '"bad"', 'String']]);
  const map = adapter.render({ name: 'm', type: '*runtime.Map[string,int]', value: '{}', variablesReference: 5 }, 'm', 'Map[String, Int]');
  assert.deepEqual((await adapter.valueChildren(adapter.handles.get(map.variablesReference), {})).map(v => [v.name, v.value, v.type]), [['k', '1', 'Int']]);
});

test('alternative cases show their case name', () => {
  const adapter = new ManuscriptAdapter(new PassThrough());
  const circle = adapter.render({ name: 's', type: 'main.Shape_Circle', value: 'main.Shape_Circle {Radius: 3}', variablesReference: 4 }, 's', 'Shape');
  assert.equal(circle.value, 'Circle');
  const viaInterface = adapter.render({ name: 's', type: 'main.Shape', value: 'main.Shape(main.Shape_Dot) {}', variablesReference: 4 }, 's', 'Shape');
  assert.equal(viaInterface.value, 'Dot');
  const unreadable = adapter.render({ name: 's', type: 'main.Shape', value: '(unreadable could not resolve interface type)', variablesReference: 4 }, 's', 'Shape');
  assert.equal(unreadable.value, 'Shape'); assert.equal(unreadable.variablesReference, 0);
});

test('native DAP source stepping and Manuscript record/list/variant rendering', { skip: !process.env.MANUSCRIPT_DAP_TEST, timeout: 60000 }, async () => {
  const directory = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'manuscript dap test ')));
  const program = path.join(directory, 'main.ms');
  const source = '\n\nimport Queue from "@std/queues.ms"\ntype Box:\n    label: String\n    count: Int\nexport fn main() -> Int:\n    let box = Box(label: "value", count: 42)\n    let items = [1, 2, 3]\n    let floats = [1.25, 2.5]\n    let bools = [true, false]\n    let strings = ["a", "b"]\n    let optional = Optional[Int].some(value: 5)\n    let queue = Queue[Int](capacity: 4)\n    queue.enqueue(value: box.count)\n    return box.count - 42 + queue.length - 1 + floats.length - 2 + bools.length - 2 + strings.length - 2\n';
  await fs.writeFile(program, source);
  const returnLine = source.split('\n').findIndex(line => line.trim().startsWith('return box.')) + 1;
  const output = new PassThrough(); const messages = []; const waiters = [];
  const adapter = new ManuscriptAdapter(output, { compiler: process.env.MANUSCRIPT_MS });
  const parser = new Framing(message => { messages.push(message); for (const wake of waiters.splice(0)) wake(); });
  output.on('data', bytes => parser.push(bytes));
  const wait = async predicate => { while (true) { const index = messages.findIndex(predicate); if (index >= 0) return messages.splice(index, 1)[0]; await new Promise(resolve => waiters.push(resolve)); } };
  let sequence = 1;
  const request = (command, args) => { const seq = sequence++; adapter.request({ seq, type: 'request', command, arguments: args }); return seq; };
  const response = async seq => { const message = await wait(message => message.request_seq === seq); assert.equal(message.success, true, message.message); return message.body; };
  try {
    const capabilities = await response(request('initialize', { adapterID: 'manuscript', linesStartAt1: true, columnsStartAt1: true, pathFormat: 'path', supportsVariableType: true }));
    assert.equal(capabilities.supportsSetVariable, false);
    assert.equal(capabilities.supportsSetExpression, false);
    const launch = request('launch', { program, stopOnEntry: false });
    const initialized = await wait(message => message.event === 'initialized' || (message.request_seq === launch && !message.success));
    assert.equal(initialized.event, 'initialized', initialized.message);
    const breakpoints = await response(request('setBreakpoints', { source: { path: program }, breakpoints: [{ line: returnLine }] }));
    assert.equal(breakpoints.breakpoints[0].verified, true);
    const configured = request('configurationDone');
    const stopped = await wait(message => message.event === 'stopped');
    await response(configured); await response(launch);
    const stack = await response(request('stackTrace', { threadId: stopped.body.threadId }));
    assert.equal(stack.stackFrames[0].name, 'main');
    for (const item of stack.stackFrames.filter(item => item.source?.path?.endsWith('.ms'))) {
      assert.equal(item.source.path, program);
      assert.ok(item.line >= 1 && item.line <= returnLine, 'runtime frame inherited a Manuscript line directive');
    }
    const scopes = await response(request('scopes', { frameId: stack.stackFrames[0].id }));
    assert.equal(scopes.scopes[0].name, 'Manuscript locals');
    assert.ok(scopes.scopes.some(scope => scope.name === 'Execution and services'));
    const locals = await response(request('variables', { variablesReference: scopes.scopes[0].variablesReference }));
    const box = locals.variables.find(variable => variable.name === 'box'); assert.equal(box.type, 'Box');
    const fields = await response(request('variables', { variablesReference: box.variablesReference }));
    assert.ok(fields.variables.find(variable => variable.name === 'count'),JSON.stringify(fields));
    assert.equal(fields.variables.find(variable => variable.name === 'count').value, '42');
    const items = locals.variables.find(variable => variable.name === 'items'); assert.equal(items.type, 'List[Int]');
    const values = await response(request('variables', { variablesReference: items.variablesReference })); assert.equal(values.variables.length, 3);
    for(const [name,want] of [['floats','1.25'],['bools','true'],['strings','"a"']]) {
      const list=locals.variables.find(variable=>variable.name===name);assert.ok(list,name);
      const expanded=await response(request('variables',{variablesReference:list.variablesReference}));assert.equal(expanded.variables.length,2,name);
      const first=await response(request('evaluate',{frameId:stack.stackFrames[0].id,expression:name+'[0]',context:'watch'}));assert.equal(first.result,want,name);
    }
    const watch = await response(request('evaluate',{frameId:stack.stackFrames[0].id,expression:'box.count',context:'watch'}));assert.equal(watch.result,'42');
    const element = await response(request('evaluate',{frameId:stack.stackFrames[0].id,expression:'items[0]',context:'watch'}));assert.equal(element.result,'1');
    const optional = locals.variables.find(variable => variable.name === 'optional'); assert.equal(optional.value, 'some');
    const payload = await response(request('variables', { variablesReference: optional.variablesReference })); assert.equal(payload.variables[0].value, '5');
    const queue = locals.variables.find(variable => variable.name === 'queue');
    assert.ok(queue, JSON.stringify(locals));
    const service = await response(request('variables', { variablesReference: queue.variablesReference }));
    assert.ok(service.variables.some(variable => variable.name === 'Queued values'), JSON.stringify(service));
    const executionScope = scopes.scopes.find(scope => scope.name === 'Execution and services');
    const runtime = await response(request('variables', { variablesReference: executionScope.variablesReference }));
    const execution = await response(request('variables', { variablesReference: runtime.variables[0].variablesReference }));
    assert.ok(execution.variables.some(variable => variable.name === 'Cancellation context'), JSON.stringify(execution));
    await response(request('disconnect', { terminateDebuggee: true }));
  } finally { await adapter.cleanup(); await fs.rm(directory, { recursive: true, force: true }); }
});

const named = names => variable => names[variable.name];

test('watch rewriting respects quoted text and native member names', () => {
  const vars = [{ name: 'box', type: '*main.Box' }, { name: 'count', type: 'int' }];
  assert.equal(rewriteExpression('box.count', vars, named({ box: 'box' })), 'box.Count');
  assert.equal(rewriteExpression('box.first_name', vars, named({ box: 'box' })), 'box.FirstName');
  assert.equal(rewriteExpression('count + len("count")', vars, named({ count: 'count' })), 'count + len("count")');
  assert.equal(rewriteExpression('total + 1', [{ name: 'sum', type: 'int' }], named({ sum: 'total' })), 'sum + 1');
});

test('watch rewriting indexes typed lists and leaves numeric literals alone', () => {
  const vars = [{ name: 'items', type: '*runtime.List[int]' }, { name: 'e5', type: 'int' }, { name: 'x1', type: 'int' }];
  assert.equal(rewriteExpression('items[2]', vars, named({ items: 'items' })), 'items.Items[2]');
  assert.equal(rewriteExpression('1e5 + e5', vars, named({ e5: 'e5' })), '1e5 + e5');
  assert.equal(rewriteExpression('0x1f + x1 + 1.5e5', vars, named({ x1: 'x1' })), '0x1f + x1 + 1.5e5');
  const separate = [{ name: 'items', type: '*github.com/manuscript-lang/manuscript/pkg/runtime.List[string]' }];
  assert.equal(rewriteExpression('items[0]', separate, named({ items: 'items' })), 'items.Items[0]');
});

test('dead native stack slots cannot masquerade as source containers', () => {
  const adapter = new ManuscriptAdapter(new PassThrough());
  const value = adapter.render({ name: 'items', type: 'string', value: '"recycled"', variablesReference: 17 }, 'items', 'List[Int]');
  assert.equal(value.type, 'List[Int]');
  assert.equal(value.value, '<unavailable after last use>');
  assert.equal(value.variablesReference, 0);
});

test('task handles and groups expose work state without native bookkeeping', async () => {
  const adapter = new ManuscriptAdapter(new PassThrough());
  const task = adapter.render({ name: 'task', type: '*runtime.Task[int]', value: '{committed: true}', variablesReference: 3 }, 'task', 'Task[Int]');
  assert.equal(task.type, 'Task[Int]');
  adapter.children = async () => [
    { name: 'id', type: '*runtime.OperationId', value: '{number: 7}', variablesReference: 0 },
    { name: 'value', type: 'int', value: '7', variablesReference: 0 },
    { name: 'committed', type: 'bool', value: 'true', variablesReference: 0 },
    { name: 'done', type: 'chan struct {}', value: 'channel', variablesReference: 0 },
  ];
  const fields = await adapter.valueChildren(adapter.handles.get(task.variablesReference), {});
  assert.deepEqual(fields.map(field => field.name), ['Operation', 'Result', 'Completed']);
  assert.equal(fields[1].value, '7'); assert.equal(fields[1].type, 'Int');
  const group = adapter.render({ name: 'group', type: '*runtime.TaskGroup', value: 'group', variablesReference: 5 }, 'group', 'TaskGroup');
  adapter.children = async () => [
    { name: 'active', type: 'int', value: '2', variablesReference: 0 },
    { name: 'sealed', type: 'bool', value: 'false', variablesReference: 0 },
    { name: 'mu', type: 'sync.Mutex', value: 'mutex', variablesReference: 0 },
  ];
  const state = await adapter.valueChildren(adapter.handles.get(group.variablesReference), {});
  assert.deepEqual(state.map(field => field.name), ['Active tasks', 'Joined']);
});

test('requests after the target ends get clear answers instead of pipe errors', async () => {
  const output = new PassThrough(); const messages = [];
  const parser = new Framing(message => messages.push(message));
  output.on('data', bytes => parser.push(bytes));
  const adapter = new ManuscriptAdapter(output);
  adapter.receive({ type: 'event', event: 'terminated', body: {} });
  assert.equal(adapter.ended, true);
  const ask = async (seq, command) => { await adapter.request({ seq, type: 'request', command, arguments: {} }); return messages.find(m => m.request_seq === seq); };
  for (const [seq, command] of [[1, 'next'], [2, 'continue'], [3, 'stepIn'], [4, 'pause']]) {
    const reply = await ask(seq, command);
    assert.equal(reply.success, false);
    assert.match(reply.message, /the debuggee has exited/);
  }
  const threads = await ask(5, 'threads');
  assert.equal(threads.success, false);
  assert.match(threads.message, /session has ended/);
  assert.doesNotMatch(JSON.stringify(messages), /TypeError|undefined/);
  for (const [seq, command] of [[6, 'terminate'], [7, 'disconnect']]) {
    const reply = await ask(seq, command);
    assert.equal(reply.success, true);
    assert.equal(reply.command, command);
  }
});
