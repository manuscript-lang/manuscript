// Manuscript's DAP layer delegates native control to Delve and renders checked
// source names and runtime values. It never evaluates application methods.
const net = require('node:net');
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
function runtimeKind(variable) {
  const text = variable.type || '';
  const match = /(?:main|msruntime)\.(Record|Alternative|List|Set|Map|Pack|Bytes|View|Unit|Function|Scheduler|Queue|PriorityQueue|Synchronized|SynchronizedGuard|OperationId)(?:\)|$)/.exec(text);
  return match ? match[1] : '';
}
function sourceType(native) {
  const primitives = { int64: 'Int', float64: 'Float', bool: 'Bool', string: 'String' };
  native = (native || '').replace(/^.+: (interface \{\}.*)$/, '$1');
  const match = /^interface \{\}\(([^)]+)\)$/.exec(native);
  return primitives[match ? match[1] : native] || native;
}
function runtimeType(key) {
  let at=0;
  function parse() {
    const start=at;while(at<key.length && !['[',']','&'].includes(key[at])) at++;
    let name=key.slice(start,at).replace(/^@std\//,'').replace(/^module\/[^#]+#/,'');
    const args=[];while(key[at]==='[') {at++;args.push(parse());if(key[at]===']') at++;}
    if(args.length) name+=`[${args.join(', ')}]`;
    return name;
  }
  return parse();
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
function rewriteExpression(expression, variables, metadata) {
  const visible=new Map();for(const variable of variables) {const local=metadata.get(variable.name);if(local) visible.set(local.name,variable);}
  const simple=/^([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_]*)|\[(\d+)\])?$/.exec(expression.trim());
  if(simple && visible.has(simple[1])) {
    const variable=visible.get(simple[1]);const kind=runtimeKind(variable);
    if(simple[2] && kind==='Record') return `${variable.name}.(main.Record).Fields[${JSON.stringify(simple[2])}]`;
    if(simple[3] && ['List','Set','Pack','Bytes'].includes(kind)) return `${variable.name}.(main.${kind}).Items[${simple[3]}]`;
    if(!simple[2] && !simple[3]) return variable.name;
  }
  let result='',at=0;
  while(at<expression.length) {
    const ch=expression[at];
    if(ch==='"' || ch==="'") {const quote=ch;result+=ch;at++;while(at<expression.length) {const char=expression[at++];result+=char;if(char==='\\' && at<expression.length) {result+=expression[at++];continue;}if(char===quote) break;}continue;}
    if(/[A-Za-z_]/.test(ch)) {const start=at++;while(at<expression.length && /[A-Za-z0-9_]/.test(expression[at])) at++;const name=expression.slice(start,at);result+=(start>0 && expression[start-1]==='.')?name:(visible.get(name)?.name || name);continue;}
    result+=ch;at++;
  }
  return result;
}
class ManuscriptAdapter {
  constructor(output, options = {}) {
    this.output = output; this.options = options; this.sequence = 1; this.backendSequence = 1;
    this.pending = new Map(); this.handles = new Map(); this.nextHandle = 1800000000;
    this.locals = new Map(); this.frames = new Set(); this.sourceScopes = new Set();
    this.entities = []; this.sourceRoot = ''; this.temp = undefined; this.ready = undefined;
  }
  emit(message) { message.seq = this.sequence++; this.output.write(frame(message)); }
  respond(request, body, success = true, message) {
    this.emit({ type: 'response', request_seq: request.seq, command: request.command, success, body, message });
  }
  async start(delve) {
    if (this.ready) return this.ready;
    this.ready = new Promise((resolve, reject) => {
      const child = spawn(delve, ['dap', '--listen=127.0.0.1:0'], { stdio: ['ignore', 'pipe', 'pipe'] });
      this.child = child; let text = ''; let connected = false;
      const timer = setTimeout(() => { child.kill(); reject(new Error('Delve startup timed out')); }, 15000);
      child.once('error', error => { clearTimeout(timer); reject(error); });
      child.once('exit', (code) => {
        clearTimeout(timer);
        if (!connected) reject(new Error(`Delve exited before startup (${code})`));
        for (const pending of this.pending.values()) pending.reject(new Error('Debugger exited'));
        this.pending.clear();
      });
      child.stderr.on('data', bytes => this.emit({ type: 'event', event: 'output', body: { category: 'stderr', output: bytes.toString() } }));
      child.stdout.on('data', bytes => {
        text += bytes.toString();
        const address = /DAP server listening at: (127\.0\.0\.1):(\d+)/.exec(text);
        if (!address || connected) return;
        connected = true; clearTimeout(timer);
        const socket = net.createConnection({ host: address[1], port: Number(address[2]) });
        this.socket = socket;
        const framing = new Framing(message => this.receive(message));
        socket.on('data', chunk => { try { framing.push(chunk); } catch (error) { this.fail(error); } });
        socket.once('connect', resolve); socket.on('error', error => { reject(error); this.fail(error); });
      });
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
    if (message.event === 'continued' || message.event === 'stopped') {
      this.handles.clear(); this.frames.clear(); this.sourceScopes.clear();
    }
    this.emit(message);
    if (message.event === 'terminated' && this.pending.size===0) this.cleanup();
  }
  handle(value) { const id = this.nextHandle++; this.handles.set(id, value); return id; }
  render(variable, name, declaredType) {
    const nativeType=sourceType(variable.type);const primitive=['Int','Float','Bool','String'].includes(nativeType);
    const embedded=/Type: \"([^\"]+)\"/.exec(variable.value || '');
    const result = { ...variable, name: name || mapName(variable.name), type: primitive ? nativeType : (embedded ? runtimeType(embedded[1]) : declaredType || nativeType) };
    result.value = (result.value || '').replace(/^interface \{\}\([^)]+\) /, '');
    if (['Int','Float','Bool','String'].includes(result.type)) result.variablesReference=0;
    const kind = runtimeKind(variable);
    // Native stack slots can cease to contain a dead source local after GC.
    // Do not present a recycled primitive or corrupt runtime type as a container.
    const expectedContainer = /^(List|Set|Map|Pack|Bytes|Optional|Result)(?:\[|$)/.exec(declaredType || '');
    if (expectedContainer && (primitive || (embedded && runtimeType(embedded[1]).split('[')[0] !== expectedContainer[1]))) {
      result.type = declaredType; result.value = '<unavailable after last use>'; result.variablesReference = 0;
      return result;
    }
    if (kind === 'Unit') { result.value = 'unit'; result.type = 'Unit'; result.variablesReference = 0; }
    else if (kind === 'OperationId') {const number=/number: (\d+)/.exec(result.value);result.value=number?`Operation ${number[1]}`:'OperationId';result.variablesReference=0;}
    else if (kind) {
      const length = /len: (\d+)/.exec(result.value);
      if (kind === 'Alternative') {
        const tag = /Tag: "([^"]+)"/.exec(result.value); result.value = tag ? tag[1] : result.type;
      } else result.value = `${result.type || kind}${length ? ` (${length[1]} items)` : ''}`;
      if (variable.variablesReference) result.variablesReference = this.handle({ kind, ref: variable.variablesReference, sourceType: result.type });
      delete result.namedVariables; delete result.indexedVariables;
    }
    return result;
  }
  async children(ref, args = {}) { return (await this.native('variables', { ...args, variablesReference: ref })).variables || []; }
  async valueChildren(handle, args) {
    let children = await this.children(handle.ref);
    for (let depth = 0; depth < 4 && children.length === 1 && ['data', '', '*'].includes(children[0].name) && children[0].variablesReference; depth++) {
      children = await this.children(children[0].variablesReference);
    }
    if (handle.kind === 'Execution') {
      const names = { Context: 'Cancellation context', Lifetime: 'Work lifetime', Owners: 'Scheduler services', HostServices: 'HTTP services' };
      return children.filter(v => names[v.name]).map(v => ({ ...v, name: names[v.name] }));
    }
    const serviceFields={PriorityQueue:{capacity:'Capacity',items:'Queued priorities',compare:'Comparator'},Queue:{capacity:'Capacity',items:'Queued values'},Synchronized:{value:'Value',holder:'Active guard'},SynchronizedGuard:{cell:'Synchronized value'},Scheduler:{limit:'Admission limit',active:'Active operations',history:'Recent outcomes',closing:'Closing',closed:'Closed'}}[handle.kind];
    if(serviceFields) return children.filter(v=>serviceFields[v.name]).map(v=>this.render(v,serviceFields[v.name]));
    const fieldName = { Record: 'Fields', Alternative: 'Fields', List: 'Items', Set: 'Items', Pack: 'Items', Bytes: 'Items', Map: 'Entries', View: 'Receiver' }[handle.kind];
    if (!fieldName) return children.map(v => this.render(v));
    const field = children.find(v => v.name === fieldName);
    if (!field || !field.variablesReference) return children.map(v => this.render(v));
    if (handle.kind === 'View') {
      const receiver = this.render(field, 'Receiver', handle.sourceType);
      const nested = this.handles.get(receiver.variablesReference);
      return nested ? this.valueChildren(nested, args) : this.children(field.variablesReference, args);
    }
    const values = await this.children(field.variablesReference, { filter: args.filter, start: args.start, count: args.count });
    // Delve includes map length metadata as a child; source views show values.
    return values.filter(v => v.name !== 'len()').map(v => this.render(v));
  }
  async loadMetadata(program, inspection) {
    const metadata = JSON.parse(await fs.readFile(`${program}.ms-build.json`, 'utf8'));
    const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
    if (!metadata.debug || digest(await fs.readFile(program)) !== metadata.executable_sha256) throw new Error('Debug executable does not match its metadata');
    this.sourceRoot = metadata.source_root;
    if (metadata.sources['ms.toml']) { if (digest(await fs.readFile(path.join(this.sourceRoot,'ms.toml'))) !== metadata.sources['ms.toml']) throw new Error('Project configuration changed since build'); }
    if (!this.sourceRoot) throw new Error('Debug build lacks source mapping');
    for (const source of inspection.sources) {
      const file = path.resolve(this.sourceRoot, source.file);
      if (metadata.sources[source.file] !== source.sha256 || digest(await fs.readFile(file)) !== source.sha256) throw new Error(`Source changed since build: ${source.file}`);
    }
    this.locals = new Map(inspection.locals.map(local => [local.go_id, local]));
    this.entities = inspection.entities.filter(e => e.kind === 'fn' || e.kind === 'method');
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
    args.mode = 'exec'; delete args.compilerPath; delete args.delvePath; delete args.inspection;
    return this.native('launch', args);
  }
  async request(request) {
    try {
      await this.start(request.arguments?.delvePath || this.options.delve || 'dlv');
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
          if (this.sourceScopes.has(args.variablesReference)) body = { variables: variables.filter(v => this.locals.has(v.name)).map(v => {
            const local = this.locals.get(v.name); return this.render(v, local.name, local.type);
          }) };
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
            args.expression = rewriteExpression(args.expression, locals, this.locals);

          }
        }
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
              this.frames.add(frame.id);
              const entities = this.entities.filter(e => path.resolve(this.sourceRoot, e.span.file) === file && e.span.line <= frame.line);
              entities.sort((a, b) => b.span.line - a.span.line);
              if (entities.length) frame.name = entities[0].name;
            } else frame.presentationHint = 'subtle';
            if (/Cleanup|Unwind|Shield/.test(frame.name)) { frame.name = `[cleanup] ${frame.name}`; frame.presentationHint = 'subtle'; }
          }
        }
        if (request.command === 'scopes' && this.frames.has(args.frameId)) {
          for (const scope of body.scopes || []) if (scope.name === 'Locals') {
            this.sourceScopes.add(scope.variablesReference); scope.name = 'Manuscript locals';
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
    if (this.child) { this.child.kill(); this.child = undefined; }
    if (this.temp) { const directory = this.temp; this.temp = undefined; await fs.rm(directory, { recursive: true, force: true }).catch(() => {}); }
  }
}
if (require.main === module) {
  const adapter = new ManuscriptAdapter(process.stdout, { compiler: process.argv[2], delve: process.argv[3] });
  const framing = new Framing(request => adapter.request(request));
  process.stdin.on('data', bytes => { try { framing.push(bytes); } catch (error) { adapter.fail(error); } });
  process.stdin.on('end', () => adapter.cleanup());
  process.on('SIGTERM', () => adapter.cleanup().then(() => process.exit(0)));
}
module.exports = { Framing, frame, ManuscriptAdapter, runtimeKind, sourceType, mapName, rewriteExpression, runtimeType };
