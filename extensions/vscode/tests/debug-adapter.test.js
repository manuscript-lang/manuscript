const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PassThrough } = require('node:stream');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { Framing, frame, ManuscriptAdapter, sourceType, mapName, rewriteExpression, runtimeType } = require(process.env.MANUSCRIPT_DAP_ADAPTER || '../debug-adapter');

test('DAP framing preserves fragmented UTF-8 and multiple messages', () => {
  const messages = []; const parser = new Framing(message => messages.push(message));
  const packet = Buffer.concat([frame({ seq: 1, text: '😀é' }), frame({ seq: 2 })]);
  for (const byte of packet) parser.push(Buffer.from([byte]));
  assert.deepEqual(messages, [{ seq: 1, text: '😀é' }, { seq: 2 }]);
  assert.throws(() => new Framing(() => {}).push(Buffer.from('Content-Length: 999999999\r\n\r\n')));
});
test('Manuscript values use source names and lazy structured handles', async () => {
  const adapter = new ManuscriptAdapter(new PassThrough());
  assert.equal(sourceType('interface {}(int64)'), 'Int');
  assert.equal(mapName('["name"]'), 'name');
  const box = adapter.render({ name: 'local5_box', type: 'interface {}(main.Record)', value: 'interface {}(main.Record) {Type: "Box", Fields: map[]}', variablesReference: 5 }, 'box', 'Box');
  assert.equal(box.name, 'box'); assert.equal(box.value, 'Box');
  const children = new Map([[5, [{ name: 'data', variablesReference: 6 }]], [6, [{ name: 'Type', value: '"Box"' }, { name: 'Fields', variablesReference: 7 }]], [7, [{ name: '["count"]', type: 'interface {}(int64)', value: 'interface {}(int64) 42', variablesReference: 0 }]]]);
  adapter.children = async ref => children.get(ref);
  const fields = await adapter.valueChildren(adapter.handles.get(box.variablesReference), {});
  assert.equal(fields[0].name, 'count'); assert.equal(fields[0].value, '42'); assert.equal(fields[0].type, 'Int');
});

test('native DAP source stepping and Manuscript record/list/variant rendering', { skip: !process.env.MANUSCRIPT_DAP_TEST, timeout: 60000 }, async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'manuscript dap test '));
  const program = path.join(directory, 'main.ms');
  const source = 'import List from "@std/collections.ms"\nimport Optional from "@std/optional.ms"\nimport Queue from "@std/queues.ms"\ntype Box:\n    label: String\n    count: Int\nexport fn main() -> Int:\n    let box = Box(label: "value", count: 42)\n    let items = [1, 2, 3]\n    let optional = Optional[Int].some(value: 5)\n    let queue = Queue[Int](capacity: 4)\n    queue.enqueue(value: box.count)\n    return box.count - 42 + queue.length() - 1\n';
  await fs.writeFile(program, source);
  const returnLine = source.split('\n').findIndex(line => line.trim().startsWith('return box.')) + 1;
  const output = new PassThrough(); const messages = []; const waiters = [];
  const adapter = new ManuscriptAdapter(output, { compiler: process.env.MANUSCRIPT_MS, delve: process.env.MANUSCRIPT_DLV });
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
    await wait(message => message.event === 'initialized');
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

test('watch rewriting respects quoted text and native member names',()=>{
 const metadata=new Map([['local5_box',{name:'box'}],['local6_count',{name:'count'}]]);
 const vars=[{name:'local5_box',type:'interface {}(main.Record)'},{name:'local6_count',type:'interface {}(int64)'}];
 assert.equal(rewriteExpression('box.count',vars,metadata),'local5_box.(data).Fields["count"]');
 assert.equal(rewriteExpression('count + len("count")',vars,metadata),'local6_count + len("count")');
});

test('nested runtime type keys render generic source types',()=>{
 assert.equal(runtimeType('@std/Result[@std/List[Int]][module/abcd#Failure]'),'Result[List[Int], Failure]');
 assert.equal(runtimeType('@std/Network'),'Network');
 const adapter=new ManuscriptAdapter(new PassThrough());
 assert.equal(adapter.render({name:'item',type:'interface {}(main.Record)',value:'interface {}(main.Record) {Type: "module/abcd#Box[Int]"}',variablesReference:1}).type,'Box[Int]');
});


test('dead native stack slots cannot masquerade as source containers', () => {
  const adapter = new ManuscriptAdapter(new PassThrough());
  const value = adapter.render({ name: 'local5_items', type: 'interface {}(string)', value: 'interface {}(string) "recycled"', variablesReference: 17 }, 'items', 'List[Int]');
  assert.equal(value.type, 'List[Int]');
  assert.equal(value.value, '<unavailable after last use>');
  assert.equal(value.variablesReference, 0);
  const specialized = adapter.render({ name: 'items', type: 'interface {}(main.List)', value: 'interface {}(main.List) {Type: "@std/List[String]", Items: []}', variablesReference: 5 }, 'items', 'List[T]');
  assert.equal(specialized.type, 'List[String]');
});

test('watch rewriting and rendering support a separately compiled runtime',()=>{
 const metadata=new Map([['local5_box',{name:'box'}],['local6_items',{name:'items'}]]);
 const vars=[{name:'local5_box',type:'interface {}(github.com/manuscript-lang/manuscript/pkg/runtime.Record)'},{name:'local6_items',type:'interface {}(*github.com/manuscript-lang/manuscript/pkg/runtime.List)'}];
 assert.equal(rewriteExpression('box.count',vars,metadata),'local5_box.(data).Fields["count"]');
 assert.equal(rewriteExpression('items[0]',vars,metadata),'local6_items.(data).Items[0]');
 const adapter = new ManuscriptAdapter(new PassThrough());
 assert.equal(adapter.render({...vars[0],value:'{Type: "Box"}',variablesReference:1}).type,'Box');
 assert.equal(adapter.render({...vars[1],value:'{Type: "@std/List[Int]"}',variablesReference:2}).type,'List[Int]');
});

test('typed task handles and groups expose work state without native bookkeeping', async () => {
  const adapter = new ManuscriptAdapter(new PassThrough());
  const task = adapter.render({ name: 'task', type: 'interface {}(*main.Task)', value: 'interface {}(*main.Task) {committed: true}', variablesReference: 3 }, 'task', 'Task[Int]');
  assert.equal(task.type, 'Task[Int]');
  adapter.children = async () => [
    { name: 'id', type: 'main.OperationId', value: '{number: 7}', variablesReference: 0 },
    { name: 'value', type: 'interface {}(int64)', value: '7', variablesReference: 0 },
    { name: 'committed', type: 'bool', value: 'true', variablesReference: 0 },
    { name: 'done', type: 'chan struct {}', value: 'channel', variablesReference: 0 },
  ];
  const fields = await adapter.valueChildren(adapter.handles.get(task.variablesReference), {});
  assert.deepEqual(fields.map(field => field.name), ['Operation', 'Result', 'Completed']);
  assert.equal(fields[1].value, '7');
  const group = adapter.render({ name: 'group', type: 'interface {}(*main.TaskGroup)', value: 'group', variablesReference: 5 }, 'group', 'TaskGroup');
  adapter.children = async () => [
    { name: 'active', type: 'int', value: '2', variablesReference: 0 },
    { name: 'sealed', type: 'bool', value: 'false', variablesReference: 0 },
    { name: 'mu', type: 'sync.Mutex', value: 'mutex', variablesReference: 0 },
  ];
  const state = await adapter.valueChildren(adapter.handles.get(group.variablesReference), {});
  assert.deepEqual(state.map(field => field.name), ['Active tasks', 'Joined']);
});
