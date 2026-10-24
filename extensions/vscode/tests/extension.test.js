const { test } = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

test('editor commands pass argument arrays, discover projects, and require trust', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'manuscript editor '));
  const commands = new Map(), builds = [], terminals = [], errors = [], clientOptions = [];
  const dispose = { dispose() {} };
  let started = false, stopped = false, provider, logSubscriptions = 0;
  const vscode = {
    workspace: {
      registerTextDocumentContentProvider: (scheme, value) => { assert.equal(scheme, "manuscript-stdlib"); provider = value; return dispose; },
      isTrusted: true, getConfiguration: () => ({ get: name => name==='serverPath' ? '/compiler path/ms' : undefined }), saveAll:async()=>true,
      getWorkspaceFolder: () => undefined, createFileSystemWatcher: () => dispose,
    },
    window: {
      activeTextEditor: { document: { languageId: 'manuscript', uri: { fsPath: path.join(root, 'src/main.ms') }, save: async () => true } },
      createOutputChannel: (name, options) => ({
        ...dispose, append() {}, appendLine() {}, show() {},
        ...(options?.log ? {
          logLevel: 3,
          trace() {}, debug() {}, info() {}, warn() {}, error() {},
          onDidChangeLogLevel: callback => {
            assert.equal(typeof callback, 'function');
            logSubscriptions++;
            return dispose;
          },
        } : {}),
      }),
      showErrorMessage: message => errors.push(message),
      showSaveDialog: async () => ({ fsPath: path.join(root, 'CPU profile.pprof') }),
      createTerminal: options => { terminals.push(options); return { show() {} }; },
    },
    commands: { registerCommand: (name, callback) => { commands.set(name, callback); return dispose; } },
  };
  const original = Module._load;
  Module._load = function (name, ...args) {
    if (name === 'vscode') return vscode;
    if (name === 'vscode-languageclient/node') return { LanguageClient: class {
      constructor(id, name, server, options) { clientOptions.push(options); this.options = options; }
      async start() {
        const traceOutputChannel = this.options.traceOutputChannel ?? this.options.outputChannel;
        traceOutputChannel.onDidChangeLogLevel(() => {});
        this.options.outputChannel.info('Language server started');
        started = true;
      }
      async stop() { stopped = true; }
      async sendRequest(method, params) { assert.equal(method, "manuscript/standardLibrarySource"); assert.equal(params.textDocument.uri, "manuscript-stdlib:/collections.ms"); return "export type List[T]:"; }
    } };
    if (name === 'node:child_process') return { execFile: (command, args, done) => { builds.push({ command, args }); done(null, '', ''); } };
    return original.call(this, name, ...args);
  };
  let extension;
  try { extension = require('../extension'); } finally { Module._load = original; }
  try {
    await fs.writeFile(path.join(root, 'ms.toml'), '[project]');
    await extension.activate({ subscriptions: [] });
    assert.equal(started, true);
    const expectedSelector = [
      { scheme: 'file', language: 'manuscript' },
      { scheme: 'manuscript-stdlib', language: 'manuscript' },
    ];
    assert.deepEqual(clientOptions[0].documentSelector, expectedSelector);
    assert.equal(await provider.provideTextDocumentContent({ toString: () => "manuscript-stdlib:/collections.ms" }), "export type List[T]:");
    await commands.get('manuscript.restartServer')();
    assert.deepEqual(clientOptions[1].documentSelector, expectedSelector);
    assert.equal(logSubscriptions, 2);
    assert.equal(clientOptions[1].outputChannel, clientOptions[0].outputChannel);
    await commands.get('manuscript.profile')();
    assert.deepEqual(terminals[0].shellArgs, ['run', path.join(root, 'ms.toml'), '--cpu-profile', path.join(root, 'CPU profile.pprof')]);
    vscode.workspace.isTrusted = false;
    await commands.get('manuscript.profile')();
    assert.equal(builds.length, 0); assert.equal(terminals.length, 1); assert.equal(errors.length, 1);
    await extension.deactivate(); assert.equal(stopped, true);
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});

test('restart recovers from a client whose start failed', async () => {
  const dispose = { dispose() {} };
  const commands = new Map(), clients = [];
  const vscode = {
    workspace: {
      registerTextDocumentContentProvider: () => dispose, isTrusted: true, getConfiguration: () => ({ get: (_, fallback) => fallback }),
      getWorkspaceFolder: () => undefined, createFileSystemWatcher: () => dispose,
    },
    window: { createOutputChannel: () => ({ ...dispose, appendLine() {}, show() {} }) },
    commands: { registerCommand: (name, callback) => { commands.set(name, callback); return dispose; } },
  };
  const original = Module._load;
  Module._load = function (name, ...args) {
    if (name === 'vscode') return vscode;
    if (name === 'vscode-languageclient/node') return { LanguageClient: class {
      constructor() { this.index = clients.push(this) - 1; }
      // The first client has no usable server: start fails and stop then rejects, as in vscode-languageclient.
      async start() { if (this.index === 0) throw new Error('spawn ms ENOENT'); this.running = true; }
      async stop() { if (this.index === 0) throw new Error("Client is not running and can't be stopped."); }
    } };
    return original.call(this, name, ...args);
  };
  let extension;
  try { delete require.cache[require.resolve('../extension')]; extension = require('../extension'); } finally { Module._load = original; }
  await assert.rejects(extension.activate({ subscriptions: [], extensionPath: '' }), /ENOENT/);
  await commands.get('manuscript.restartServer')();
  assert.equal(clients.length, 2);
  assert.equal(clients[1].running, true);
  await extension.deactivate();
});

test('language configuration indents block openers and dedents only else', () => {
  const rules = require('../language-configuration.json').indentationRules;
  const increase = new RegExp(rules.increaseIndentPattern), decrease = new RegExp(rules.decreaseIndentPattern);
  for (const line of ['def main() -> Unit:', 'if x: # note', '    else:']) assert.ok(increase.test(line), line);
  for (const line of ['# note:', '    # heading:', 'let x = 1']) assert.ok(!increase.test(line), line);
  assert.ok(decrease.test('    elif y:'));
  assert.ok(!decrease.test('    case Done'));
});

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function lifecycleFixture(options = {}) {
  const clients = [], commands = new Map(), watchers = [], requests = [], searches = [], tasks = [], logs = [];
  const disposable = { dispose() {} };
  let provider, taskProvider, configurationChanged, serverPath = 'ms';
  const output = {
    ...disposable, logLevel: 3, trace() {}, debug() {}, info() {}, warn() {}, error() {},
    onDidChangeLogLevel: () => disposable, appendLine: message => logs.push(message), show() {},
  };
  const vscode = {
    workspace: {
      getConfiguration: () => ({ get: () => serverPath }),
      createFileSystemWatcher: pattern => { watchers.push(pattern); return disposable; },
      registerTextDocumentContentProvider: (_, value) => { provider = value; return disposable; },
      onDidChangeConfiguration: callback => { configurationChanged = callback; return disposable; },
      getWorkspaceFolder: () => undefined,
      findFiles: async (...args) => { searches.push(args); return options.findFiles ? options.findFiles(...args) : []; },
    },
    window: { createOutputChannel: (_, settings) => { assert.equal(settings.log, true); return output; } },
    commands: { registerCommand: (name, callback) => { commands.set(name, callback); return disposable; } },
    tasks: { registerTaskProvider: (_, value) => { taskProvider = value; return disposable; } },
    Task: class { constructor(...args) { this.args = args; tasks.push(this); options.taskCreated?.(this); } },
    ProcessExecution: class { constructor(...args) { this.args = args; } },
    TaskGroup: { Build: 'Build', Test: 'Test' },
  };
  class Client {
    constructor(id, name, server, settings) {
      this.index = clients.length; this.server = server; this.options = settings;
      this.stopCalls = 0; this.running = false; clients.push(this);
    }
    async start() {
      // Exercise the log-channel API required by the actual pinned client.
      this.options.outputChannel.onDidChangeLogLevel(() => {});
      this.options.outputChannel.info('starting');
      await options.start?.(this);
      this.running = true;
    }
    async stop() { this.stopCalls++; await options.stop?.(this); this.running = false; }
    async sendRequest(...args) { requests.push(args); return 'standard source'; }
  }
  const original = Module._load;
  Module._load = function(name, ...args) {
    if (name === 'vscode') return vscode;
    if (name === 'vscode-languageclient/node') return { LanguageClient: Client };
    return original.call(this, name, ...args);
  };
  let extension;
  try { delete require.cache[require.resolve('../extension')]; extension = require('../extension'); }
  finally { Module._load = original; }
  return {
    extension, clients, watchers, requests, searches, tasks, logs,
    activate: () => extension.activate({ subscriptions: [], extensionPath: '' }),
    restart: () => commands.get('manuscript.restartServer')(),
    content: (token) => provider.provideTextDocumentContent({ toString: () => 'manuscript-stdlib:/collections.ms' }, token),
    provideTasks: token => taskProvider.provideTasks(token),
    configure: value => { serverPath = value; configurationChanged({ affectsConfiguration: key => key === 'manuscript.serverPath' }); },
  };
}

test('watcher ignores unrelated TOML while covering Manuscript sources and manifests', async () => {
  const fixture = lifecycleFixture();
  await fixture.activate();
  try {
    const watched = file => fixture.watchers.some(pattern => path.matchesGlob(file, pattern));
    for (const file of ['main.ms', 'src/main.ms', 'ms.toml', 'nested/project/ms.toml']) assert.ok(watched(file), file);
    for (const file of ['config.toml', 'nested/Cargo.toml', 'src/main.go', 'nested/not-ms.toml']) assert.ok(!watched(file), file);
  } finally { await fixture.extension.deactivate(); }
});

test('content and task providers propagate cancellation and stop canceled discovery', async () => {
  const search = deferred(), manifests = Array.from({ length: 1000 }, (_, n) => ({ fsPath: `/project${n}/ms.toml` }));
  const token = { isCancellationRequested: false };
  const fixture = lifecycleFixture({ findFiles: () => search.promise });
  await fixture.activate();
  try {
    await fixture.content(token);
    assert.equal(fixture.requests[0][2], token);
    const pending = fixture.provideTasks(token);
    assert.equal(fixture.searches[0][3], token);
    token.isCancellationRequested = true;
    search.resolve(manifests);
    assert.deepEqual(await pending, []);
    assert.equal(fixture.tasks.length, 0);
    assert.deepEqual(await fixture.provideTasks(token), []);
    assert.equal(fixture.searches.length, 1, 'pre-canceled discovery must not scan');
    await fixture.content(token);
    assert.equal(fixture.requests.length, 1, 'pre-canceled content must not send a request');
    token.isCancellationRequested = false;
    assert.equal((await fixture.provideTasks(token)).length, 4000, 'uncanceled discovery retains all projects');
  } finally { await fixture.extension.deactivate(); }
});

test('task creation stops when cancellation arrives during enumeration', async () => {
  const token = { isCancellationRequested: false };
  const fixture = lifecycleFixture({
    findFiles: () => [{ fsPath: '/project/ms.toml' }, { fsPath: '/other/ms.toml' }],
    taskCreated: () => { token.isCancellationRequested = true; },
  });
  await fixture.activate();
  try {
    assert.deepEqual(await fixture.provideTasks(token), []);
    assert.equal(fixture.tasks.length, 1);
  } finally { await fixture.extension.deactivate(); }
});

test('overlapping restart commands and config changes own one replacement', async () => {
  const stopped = deferred(), stopping = deferred();
  const fixture = lifecycleFixture({ stop: client => { if (client.index === 0) { stopping.resolve(); return stopped.promise; } } });
  await fixture.activate();
  const pending = Array.from({ length: 20 }, () => fixture.restart());
  await stopping.promise;
  fixture.configure('/new/ms');
  fixture.configure('/latest/ms');
  assert.equal(fixture.clients[0].stopCalls, 1);
  stopped.resolve();
  await Promise.all(pending);
  assert.equal(fixture.clients.length, 2);
  assert.equal(fixture.clients[1].server.command, '/latest/ms');
  assert.equal(fixture.clients.filter(client => client.running).length, 1);
  await fixture.extension.deactivate();
  assert.equal(fixture.clients.filter(client => client.running).length, 0);
});

test('configuration changed during replacement startup is applied before restart completes', async () => {
  const starting = deferred(), started = deferred();
  const fixture = lifecycleFixture({ start: client => { if (client.index === 1) { starting.resolve(); return started.promise; } } });
  await fixture.activate();
  const pending = fixture.restart();
  await starting.promise;
  fixture.configure('/latest/ms');
  started.resolve();
  await pending;
  assert.equal(fixture.clients.length, 3);
  assert.equal(fixture.clients[1].stopCalls, 1);
  assert.equal(fixture.clients[2].server.command, '/latest/ms');
  assert.equal(fixture.clients.filter(client => client.running).length, 1);
  await fixture.extension.deactivate();
});

test('deactivate joins replacement startup and refuses further restart requests', async () => {
  const starting = deferred(), started = deferred();
  const fixture = lifecycleFixture({ start: client => { if (client.index === 1) { starting.resolve(); return started.promise; } } });
  await fixture.activate();
  const pending = fixture.restart();
  await starting.promise;
  let deactivated = false;
  const shutdown = fixture.extension.deactivate().then(() => { deactivated = true; });
  await fixture.restart();
  await Promise.resolve();
  assert.equal(deactivated, false);
  assert.equal(fixture.clients[1].stopCalls, 0, 'do not stop a client while it is starting');
  started.resolve();
  await Promise.all([pending, shutdown]);
  assert.equal(fixture.clients.length, 2);
  assert.equal(fixture.clients.filter(client => client.running).length, 0);
});

test('restart joins initial startup and shutdown can suppress its replacement', async () => {
  const starting = deferred(), started = deferred();
  const fixture = lifecycleFixture({ start: () => { starting.resolve(); return started.promise; } });
  const activation = fixture.activate();
  await starting.promise;
  const pending = fixture.restart();
  const shutdown = fixture.extension.deactivate();
  assert.equal(fixture.clients[0].stopCalls, 0);
  started.resolve();
  await Promise.all([activation, pending, shutdown]);
  assert.equal(fixture.clients.length, 1);
  assert.equal(fixture.clients[0].running, false);
  assert.equal(fixture.clients[0].stopCalls, 1);
});

test('failed replacement startup is cleaned up and restart remains usable', async () => {
  const fixture = lifecycleFixture({ start: client => { if (client.index === 1) throw new Error('replacement failed'); } });
  await fixture.activate();
  await fixture.restart();
  assert.equal(fixture.clients[1].stopCalls, 1);
  assert.ok(fixture.logs.includes('replacement failed'));
  await fixture.restart();
  assert.equal(fixture.clients.length, 3);
  assert.equal(fixture.clients[2].running, true);
  await fixture.extension.deactivate();
  assert.equal(fixture.clients.filter(client => client.running).length, 0);
});

test('content requests use the recovered client after initial startup fails', async () => {
  const fixture = lifecycleFixture({
    start: client => { if (client.index === 0) throw new Error('missing binary'); },
    stop: client => { if (client.index === 0) throw new Error('not running'); },
  });
  await assert.rejects(fixture.activate(), /missing binary/);
  await fixture.restart();
  assert.equal(await fixture.content({ isCancellationRequested: false }), 'standard source');
  assert.equal(fixture.clients[0].stopCalls, 1);
  await fixture.extension.deactivate();
  assert.equal(fixture.clients.filter(client => client.running).length, 0);
});
