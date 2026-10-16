// Manuscript's DAP layer delegates native control to Delve and renders checked
// source names and runtime values. It never evaluates application methods.
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawn, execFile } = require('node:child_process');

class Framing {
  constructor(receive) { this.buffer = Buffer.alloc(0); this.receive = receive; }
  push(bytes) {
    this.buffer = Buffer.concat([this.buffer, bytes]);
    while (true) {
      const separator = this.buffer.indexOf('\r\n\r\n');
      if (separator < 0) { if (this.buffer.length > 8192) throw new Error('DAP header too large'); return; }
      const match = /(?:^|\r\n)Content-Length: (\d+)(?:\r\n|$)/i.exec(this.buffer.subarray(0, separator).toString());
      if (!match) throw new Error('Missing Content-Length');
      const length = Number(match[1]);
      if (length > 16 * 1024 * 1024) throw new Error('DAP message too large');
      if (this.buffer.length < separator + 4 + length) return;
      const body = this.buffer.subarray(separator + 4, separator + 4 + length);
      this.buffer = this.buffer.subarray(separator + 4 + length);
      this.receive(JSON.parse(body.toString()));
    }
  }
}
function frame(message) {
  const body = Buffer.from(JSON.stringify(message));
  return Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`), body]);
}
function exec(command, args) {
  return new Promise((resolve, reject) => execFile(command, args, { maxBuffer: 32 * 1024 * 1024 },
    (error, stdout, stderr) => error ? reject(new Error(stderr || error.message)) : resolve(stdout)));
}
const PRIMITIVES = { int64: 'Int', float64: 'Float', bool: 'Bool', string: 'String' };
// Standard values lower to generic Go types in the runtime package, whatever
// its import path or vendored package name.
const RUNTIME_TYPE = /^\*?(?:[\w.\/-]*\/)?(?:ms)?runtime\.(\w+)(?:\[.*)?$/;
// Source container types and the runtime type each one lowers to.
const CONTAINERS = { List: 'List', Set: 'Set', Map: 'Map', Bytes: 'Bytes', Queue: 'Queue', PriorityQueue: 'PriorityQueue', Optional: 'Option', Result: 'Result' };
function runtimeKind(variable) {
  const text = variable.type || '';
  const std = RUNTIME_TYPE.exec(text);
  if (std) return std[1];
  // Records, alternative cases and contracts lower to generated Go types.
  if (/^\*?main\.\w+(?:\[.*\])?$/.test(text)) return 'Record';
  if (text.startsWith('[]')) return 'Slice';
  return '';
}
function sourceType(native) {
  native = (native || '').replace(/^\*/, '');
  if (PRIMITIVES[native]) return PRIMITIVES[native];
  return native.replace(/(?:[\w.-]+\/)*(?:ms)?runtime\./g, '').replace(/\bmain\./g, '').replace(/\*/g, '')
    .replace(/\b(int64|float64|bool|string)\b/g, name => PRIMITIVES[name]).replace(/\bOption\b/g, 'Optional');
}
// Go field names are the CamelCase of the source field names.
function sourceField(goName) { return goName.replace(/([a-z0-9])([A-Z])/g, '$1_$2').replace(/^./, c => c.toLowerCase()).toLowerCase(); }
function goField(name) { return name.replace(/(^|_)([a-z])/g, (_, __, c) => c.toUpperCase()).replace(/_/g, ''); }
function typeArguments(type) {
  const open = (type || '').indexOf('[');
  if (open < 0 || !type.endsWith(']')) return [];
  const args = []; let depth = 0, start = open + 1;
  for (let at = open + 1; at < type.length - 1; at++) {
    const ch = type[at];
    if ('[('.includes(ch)) depth++;
    else if ('])'.includes(ch)) depth--;
    else if (ch === ',' && depth === 0) { args.push(type.slice(start, at).trim()); start = at + 1; }
  }
  args.push(type.slice(start, type.length - 1).trim());
  return args;
}
function mapName(name) {
  if (name.startsWith('[') && name.endsWith(']')) {
    try { const key = JSON.parse(name.slice(1, -1)); if (typeof key === 'string') return key; } catch {}
  }
  if (name.startsWith('"')) { try { const key=JSON.parse(name); if(typeof key==='string') return key; } catch {} }
  return name;
}
// Resolve source identifiers and simple record/list access without rewriting
// quoted text or member names. Complex expressions keep Delve's native semantics.
// resolve maps a native variable to the source name it holds in the frame.
function rewriteExpression(expression, variables, resolve) {
  const visible = new Map();
  for (const variable of variables) { const name = resolve(variable); if (name) visible.set(name, variable); }
  const simple = /^([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_]*)|\[(\d+)\])?$/.exec(expression.trim());
  if (simple && visible.has(simple[1])) {
    const variable = visible.get(simple[1]); const kind = runtimeKind(variable);
    if (simple[2] && kind === 'Record') return `${variable.name}.${goField(simple[2])}`;
    if (simple[3] && kind === 'List') return `${variable.name}.Items[${simple[3]}]`;
    if (simple[3] && kind === 'Bytes') return `${variable.name}.Data[${simple[3]}]`;
    if (!simple[2] && !simple[3]) return variable.name;
  }
  let result='',at=0;
  while(at<expression.length) {
    const ch=expression[at];
    if(ch==='"' || ch==="'") {const quote=ch;result+=ch;at++;while(at<expression.length) {const char=expression[at++];result+=char;if(char==='\\' && at<expression.length) {result+=expression[at++];continue;}if(char===quote) break;}continue;}
    if(/[0-9]/.test(ch)) {const start=at++;while(at<expression.length && (/[A-Za-z0-9_]/.test(expression[at]) || (expression[at]==='.' && /[0-9]/.test(expression[at+1]||'')))) at++;result+=expression.slice(start,at);continue;}
    if(/[A-Za-z_]/.test(ch)) {const start=at++;while(at<expression.length && /[A-Za-z0-9_]/.test(expression[at])) at++;const name=expression.slice(start,at);result+=(start>0 && expression[start-1]==='.')?name:(visible.get(name)?.name || name);continue;}
    result+=ch;at++;
  }
  return result;
}
class ManuscriptAdapter {
  constructor(output, options = {}) {
    this.output = output; this.options = options; this.sequence = 1; this.backendSequence = 1;
    this.pending = new Map(); this.handles = new Map(); this.nextHandle = 1800000000;
    this.locals = new Map(); this.frames = new Map(); this.sourceScopes = new Map();
    this.entities = []; this.sourceRoot = ''; this.temp = undefined; this.ready = undefined;
  }
  emit(message) { message.seq = this.sequence++; this.output.write(frame(message)); }
  respond(request, body, success = true, message) {
    this.emit({ type: 'response', request_seq: request.seq, command: request.command, success, body, message });
  }
  async start(compiler) {
    if (this.ready) return this.ready;
    this.ready = new Promise((resolve, reject) => {
      const child = spawn(compiler, ['dap'], { stdio: ['pipe', 'pipe', 'pipe'] });
      this.child = child;
      child.once('error', reject);
      child.once('spawn', resolve);
      child.once('exit', () => {
        for (const pending of this.pending.values()) pending.reject(new Error('Debugger exited'));
        this.pending.clear();
      });
      child.stderr.on('data', bytes => this.emit({ type: 'event', event: 'output', body: { category: 'stderr', output: bytes.toString() } }));
      this.socket = child.stdin;
      this.socket.on('error', error => this.fail(error));
      const framing = new Framing(message => this.receive(message));
      child.stdout.on('data', bytes => { try { framing.push(bytes); } catch (error) { this.fail(error); } });
    });
    return this.ready;
  }
  native(command, args) {
    return new Promise((resolve, reject) => {
      const seq = this.backendSequence++;
      this.pending.set(seq, { resolve, reject });
      this.socket.write(frame({ seq, type: 'request', command, arguments: args }));
    });
  }
  receive(message) {
    if (message.type === 'response') {
      const pending = this.pending.get(message.request_seq);
      if (pending) { this.pending.delete(message.request_seq); message.success ? pending.resolve(message.body || {}) : pending.reject(new Error(message.message || 'Debugger request failed')); }
      return;
    }
    if (message.event === 'terminated') this.ended = true;
    if (message.event === 'continued' || message.event === 'stopped') {
      this.handles.clear(); this.frames.clear(); this.sourceScopes.clear();
    }
    this.emit(message);
    if (message.event === 'terminated' && this.pending.size===0) this.cleanup();
  }
  // The Go local a native variable name stands for in the frame's function.
  localFor(goName, frameName) {
    const candidates = this.locals.get(goName);
    if (!candidates) return undefined;
    return candidates.find(c => c.function === frameName || frameName?.endsWith(`.${c.function}`) || frameName?.endsWith(` ${c.function}`)) || candidates[0];
  }
  handle(value) { const id = this.nextHandle++; this.handles.set(id, value); return id; }
  render(variable, name, declaredType) {
    const raw = variable.type || '';
    const primitive = PRIMITIVES[raw];
    const kind = runtimeKind(variable);
    const result = { ...variable, name: name ?? mapName(variable.name), type: declaredType || primitive || sourceType(raw) };
    result.value = result.value || '';
    delete result.namedVariables; delete result.indexedVariables;
    const expected = CONTAINERS[(declaredType || '').split('[')[0]];
    // Native stack slots can cease to contain a dead source local after GC.
    // Do not present a recycled value of another type as the declared container.
    if (expected && kind !== expected) { result.value = '<unavailable after last use>'; result.variablesReference = 0; return result; }
    if (primitive) { result.variablesReference = 0; return result; }
    if (kind === 'Unit' || declaredType === 'Unit') { result.value = 'unit'; result.type = 'Unit'; result.variablesReference = 0; return result; }
    if (kind === 'OperationId') { const number = /number: (\d+)/.exec(result.value); result.value = number ? `Operation ${number[1]}` : 'OperationId'; result.variablesReference = 0; return result; }
    if (!kind) return result;
    const count = pattern => { const match = pattern.exec(result.value); return match ? ` (${match[1]} items)` : ''; };
    let handled = true;
    if (kind === 'Option') {
      const some = /Some: (true|false)/.exec(result.value);
      result.value = some && some[1] === 'true' ? 'some' : 'none';
      handled = result.value === 'some';
    } else if (kind === 'Result') {
      const failed = /Failed: (true|false)/.exec(result.value);
      result.value = failed && failed[1] === 'true' ? 'failed' : 'ok';
    } else if (kind === 'List') result.value = `${result.type}${count(/len: (\d+)/)}`;
    else if (kind === 'Map') result.value = `${result.type}${count(/live: (\d+)/)}`;
    else if (kind === 'Queue') result.value = `${result.type}${count(/items: [^{]*?len: (\d+)/)}`;
    else if (kind === 'Slice') result.value = `${result.type}${count(/len: (\d+)/)}`;
    else if (kind === 'Record') {
      // A case of an alternative lowers to Name_Case; the dynamic type of a
      // contract or alternative variable is named in its value.
      const dynamic = /^main\.\w+\(\*?main\.(\w+)\)/.exec(result.value);
      const goName = dynamic ? dynamic[1] : raw.replace(/^\*?main\./, '').replace(/\[.*$/, '');
      const base = (declaredType || '').split('[')[0];
      result.value = base && goName.startsWith(`${base}_`) ? goName.slice(base.length + 1) : (declaredType || sourceType(raw));
      if (/unreadable/.test(variable.value || '')) { result.value = declaredType || sourceType(raw); handled = false; }
    } else result.value = result.type;
    if (variable.variablesReference && handled) result.variablesReference = this.handle({ kind, ref: variable.variablesReference, sourceType: result.type });
    else result.variablesReference = 0;
    return result;
  }
  async children(ref, args = {}) { return (await this.native('variables', { ...args, variablesReference: ref })).variables || []; }
  async valueFields(ref) {
    let children = await this.children(ref);
    for (let depth = 0; depth < 4 && children.length === 1 && ['data', '', '*'].includes(children[0].name) && children[0].variablesReference; depth++) {
      children = await this.children(children[0].variablesReference);
    }
    return children;
  }
  // Entries of a map's backing slice; removed entries are nil and skipped.
  async entries(ref, args) {
    const fields = await this.valueFields(ref);
    const slice = fields.find(v => v.name === 'entries');
    if (!slice?.variablesReference) return [];
    const result = [];
    for (const entry of await this.children(slice.variablesReference, args)) {
      if (!entry.variablesReference) continue;
      const parts = await this.valueFields(entry.variablesReference);
      result.push({ key: parts.find(v => v.name === 'Key'), value: parts.find(v => v.name === 'Value') });
    }
    return result;
  }
  async valueChildren(handle, args) {
    const types = typeArguments(handle.sourceType);
    if (handle.kind === 'Execution') {
      const children = await this.valueFields(handle.ref);
      const names = { Context: 'Cancellation context', Lifetime: 'Work lifetime', Owners: 'Scheduler services', TaskGroups: 'Task groups', HostServices: 'HTTP services' };
      return children.filter(v => names[v.name]).map(v => ({ ...v, name: names[v.name] }));
    }
    const children = await this.valueFields(handle.ref);
    const serviceFields={TaskGroup:{active:'Active tasks',sealed:'Joined',closing:'Closing',closed:'Closed',failure:'Execution failure'},Task:{id:'Operation',value:'Result',committed:'Completed',group:'Task group'},PriorityQueue:{capacity:'Capacity',items:'Queued priorities',compare:'Comparator'},Queue:{capacity:'Capacity',items:'Queued values'},Synchronized:{value:'Value',holder:'Active guard'},SynchronizedGuard:{cell:'Synchronized value'},Scheduler:{limit:'Admission limit',active:'Active operations',history:'Recent outcomes',closing:'Closing',closed:'Closed'}}[handle.kind];
    if (serviceFields) return children.filter(v=>serviceFields[v.name]).map(v=>this.render(v,serviceFields[v.name],handle.kind==='Task'&&v.name==='value'?types[0]:undefined));
    switch (handle.kind) {
      case 'Record': return children.filter(v => /^[A-Z]/.test(v.name)).map(v => this.render(v, sourceField(v.name)));
      case 'Option': return children.filter(v => v.name === 'Val').map(v => this.render(v, 'value', types[0]));
      case 'Result': {
        const failed = children.find(v => v.name === 'Failed')?.value === 'true';
        return children.filter(v => v.name === (failed ? 'Err' : 'Val')).map(v => this.render(v, failed ? 'error' : 'value', types[failed ? 1 : 0]));
      }
      case 'Slice': return (await this.children(handle.ref, args)).map(v => this.render(v, v.name, types[0]));
      case 'List': case 'Bytes': {
        const items = children.find(v => v.name === (handle.kind === 'List' ? 'Items' : 'Data'));
        if (!items?.variablesReference) return [];
        return (await this.children(items.variablesReference, args)).map(v => this.render(v, v.name, types[0]));
      }
      case 'Map': {
        const shown = await this.entries(handle.ref, args);
        return shown.filter(e => e.key && e.value).map(e => this.render(e.value, mapName(e.key.value), types[1]));
      }
      case 'Set': {
        const inner = children.find(v => v.name === 'm');
        const shown = inner?.variablesReference ? await this.entries(inner.variablesReference, args) : [];
        return shown.filter(e => e.key).map((e, index) => this.render(e.key, `[${index}]`, types[0]));
      }
      default: return children.map(v => this.render(v));
    }
  }
  async loadMetadata(program, inspection) {
    const metadata = JSON.parse(await fs.readFile(`${program}.ms-build.json`, 'utf8'));
    const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
    if (!metadata.debug || digest(await fs.readFile(program)) !== metadata.executable_sha256) throw new Error('Debug executable does not match its metadata');
    this.sourceRoot = metadata.source_root;
    if (!this.sourceRoot) throw new Error('Debug build lacks source mapping');
    if (metadata.sources['ms.toml']) { if (digest(await fs.readFile(path.join(this.sourceRoot,'ms.toml'))) !== metadata.sources['ms.toml']) throw new Error('Project configuration changed since build'); }
    for (const source of inspection.sources) {
      const file = path.resolve(this.sourceRoot, source.file);
      if (metadata.sources[source.file] !== source.sha256 || digest(await fs.readFile(file)) !== source.sha256) throw new Error(`Source changed since build: ${source.file}`);
    }
    this.locals = new Map();
    for (const local of inspection.go_locals || []) {
      if (!this.locals.has(local.go)) this.locals.set(local.go, []);
      this.locals.get(local.go).push(local);
    }
    this.entities = inspection.entities.filter(e => e.kind === 'fn' || e.kind === 'method' || e.kind === 'accessor' && e.go_id);
  }
  async launch(args) {
    args = { ...args };
    const compiler = args.compilerPath || this.options.compiler || 'ms';
    const program = args.program;
    if (!program) throw new Error('launch.program must name a Manuscript module or project');
    if (program.endsWith('.ms') || path.basename(program) === 'ms.toml') {
      let target = path.resolve(program);
      if (target.endsWith('.ms')) for (let dir = path.dirname(target); ; dir = path.dirname(dir)) {
        const candidate = path.join(dir, 'ms.toml');
        try { await fs.access(candidate); target = candidate; break; } catch (error) { if (error.code !== 'ENOENT') throw error; }
        if (path.dirname(dir) === dir) break;
      }
      this.temp = await fs.mkdtemp(path.join(os.tmpdir(), 'manuscript-dap-'));
      args.program = path.join(this.temp, process.platform === 'win32' ? 'program.exe' : 'program');
      await exec(compiler, ['build', target, '--debug', '-o', args.program]);
      const inspection = JSON.parse(await exec(compiler, ['inspect', target]));
      await this.loadMetadata(args.program, inspection);
      args.cwd = args.cwd || path.dirname(target);
    } else {
      if (!args.inspection) throw new Error('Prebuilt launches require an inspection.json path');
      await this.loadMetadata(program, JSON.parse(await fs.readFile(args.inspection, 'utf8')));
    }
    args.mode = 'exec'; args.outputMode = 'remote'; delete args.compilerPath; delete args.inspection;
    return this.native('launch', args);
  }
  // After terminated the debugger process is gone. Requests that cannot succeed
  // get a clear answer instead of a failure writing to a closed pipe.
  async endedRequest(request) {
    if (request.command === 'disconnect' || request.command === 'terminate') {
      await this.cleanup();
      return this.respond(request, {});
    }
    const resumes = ['continue', 'next', 'stepIn', 'stepOut', 'stepBack', 'reverseContinue', 'pause'];
    this.respond(request, {}, false, resumes.includes(request.command)
      ? `the debuggee has exited: ${request.command} has nothing to resume`
      : `the debug session has ended: ${request.command} is no longer available`);
  }
  async request(request) {
    if (this.ended) return this.endedRequest(request);
    try {
      await this.start(request.arguments?.compilerPath || this.options.compiler || 'ms');
      const args = request.arguments || {}; let body;
      if (request.command === 'launch') body = await this.launch(args);
      else if (request.command === 'variables') {
        const handle = this.handles.get(args.variablesReference);
        if (handle?.kind === 'runtime') {
          const locals = await this.children(handle.ref);
          const ctx = locals.find(v => v.name === 'ctx');
          body = { variables: ctx?.variablesReference ? [{ ...ctx, name: 'Execution', variablesReference: this.handle({ kind: 'Execution', ref: ctx.variablesReference }) }] : [] };
        } else if (handle) body = { variables: await this.valueChildren(handle, args) };
        else {
          const variables = await this.children(args.variablesReference, args);
          if (this.sourceScopes.has(args.variablesReference)) {
            const frameName = this.sourceScopes.get(args.variablesReference);
            body = { variables: variables.filter(v => this.localFor(v.name, frameName)).map(v => {
              const local = this.localFor(v.name, frameName); return this.render(v, local.name, local.type);
            }) };
          }
          else body = { variables: variables.map(v => this.render(v)) };
        }
      } else {
        if (request.command === 'evaluate') {
          // Preserve expression semantics; source local identifiers are mapped to
          // generated names using the selected frame's actual local scope.
          const scopes = await this.native('scopes', { frameId: args.frameId });
          const localScope = scopes.scopes?.find(s => s.name === 'Locals');
          if (localScope) {
            const locals = await this.children(localScope.variablesReference);
            args.expression = rewriteExpression(args.expression, locals, variable => this.localFor(variable.name, this.frames.get(args.frameId))?.name);
          }
        }
        // Rendering classifies values by their native type, so Delve must report it.
        if (request.command === 'initialize') args.supportsVariableType = true;
        body = await this.native(request.command, args);
        if (request.command === 'initialize') {
          // Source value handles are inspection views; native mutation cannot
          // safely reuse mapped names, generic types, or synthetic handles.
          body.supportsSetVariable = false; body.supportsSetExpression = false;
        }
        if (request.command === 'stackTrace') {
          for (const frame of body.stackFrames || []) {
            const file = frame.source?.path;
            if (file?.endsWith('.ms')) {
              const entities = this.entities.filter(e => path.resolve(this.sourceRoot, e.span.file) === file && e.span.line <= frame.line);
              entities.sort((a, b) => b.span.line - a.span.line);
              if (entities.length) frame.name = entities[0].name;
              this.frames.set(frame.id, frame.name);
            } else frame.presentationHint = 'subtle';
            if (/Cleanup|Unwind|Shield/.test(frame.name)) { frame.name = `[cleanup] ${frame.name}`; frame.presentationHint = 'subtle'; }
          }
        }
        if (request.command === 'scopes' && this.frames.has(args.frameId)) {
          for (const scope of body.scopes || []) if (scope.name === 'Locals') {
            this.sourceScopes.set(scope.variablesReference, this.frames.get(args.frameId)); scope.name = 'Manuscript locals';
            body.scopes.push({ name: 'Execution and services', variablesReference: this.handle({ kind: 'runtime', ref: scope.variablesReference }), expensive: false });
          }
        }
        if (request.command === 'evaluate') {const rendered=this.render({...body,name:'',value:body.result});body={result:rendered.value,type:rendered.type,variablesReference:rendered.variablesReference};}
      }
      this.respond(request, body);
      if (request.command === 'disconnect') await this.cleanup();
    } catch (error) { this.respond(request, {}, false, error.message); if (request.command === 'launch') await this.cleanup(); }
  }
  fail(error) { this.emit({ type: 'event', event: 'output', body: { category: 'stderr', output: `${error.message}\n` } }); this.cleanup(); }
  async cleanup() {
    if (this.socket) { this.socket.destroy(); this.socket = undefined; }
    if (this.child) {
      const child = this.child; this.child = undefined;
      await new Promise(resolve => {
        if (child.exitCode !== null || child.signalCode !== null) return resolve();
        const timer = setTimeout(() => child.kill('SIGKILL'), 5000);
        child.once('close', () => { clearTimeout(timer); resolve(); });
        // Closing stdin lets ms detach/reap the target before it exits, including
        // on Windows where child.kill() would terminate ms immediately.
      });
    }
    if (this.temp) { const directory = this.temp; this.temp = undefined; await fs.rm(directory, { recursive: true, force: true }).catch(() => {}); }
  }
}
if (require.main === module) {
  const adapter = new ManuscriptAdapter(process.stdout, { compiler: process.argv[2] });
  const framing = new Framing(request => adapter.request(request));
  process.stdin.on('data', bytes => { try { framing.push(bytes); } catch (error) { adapter.fail(error); } });
  process.stdin.on('end', () => adapter.cleanup());
  process.on('SIGTERM', () => adapter.cleanup().then(() => process.exit(0)));
}
module.exports = { Framing, frame, ManuscriptAdapter, runtimeKind, sourceType, mapName, rewriteExpression, goField, sourceField, typeArguments };
