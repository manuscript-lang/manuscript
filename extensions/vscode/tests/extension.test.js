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
  let started = false, stopped = false, debugConfig, provider;
  const vscode = {
    workspace: {
      registerTextDocumentContentProvider: (scheme, value) => { assert.equal(scheme, "manuscript-stdlib"); provider = value; return dispose; },
      isTrusted: true, getConfiguration: () => ({ get: name => name==='serverPath' ? '/compiler path/ms' : undefined }), saveAll:async()=>true,
      getWorkspaceFolder: () => undefined, createFileSystemWatcher: () => dispose,
    },
    window: {
      activeTextEditor: { document: { languageId: 'manuscript', uri: { fsPath: path.join(root, 'src/main.ms') }, save: async () => true } },
      createOutputChannel: () => ({ ...dispose, append() {}, appendLine() {}, show() {} }),
      showErrorMessage: message => errors.push(message),
      showSaveDialog: async () => ({ fsPath: path.join(root, 'CPU profile.pprof') }),
      createTerminal: options => { terminals.push(options); return { show() {} }; },
    },
    commands: { registerCommand: (name, callback) => { commands.set(name, callback); return dispose; } },
    debug: {
      onDidTerminateDebugSession: () => dispose,
 registerDebugAdapterDescriptorFactory:()=>dispose,registerDebugConfigurationProvider:()=>dispose,
      startDebugging: async (_, config) => { debugConfig = config; return false; },
    },
  };
  const original = Module._load;
  Module._load = function (name, ...args) {
    if (name === 'vscode') return vscode;
    if (name === 'vscode-languageclient/node') return { LanguageClient: class {
      constructor(id, name, server, options) { clientOptions.push(options); }
      async start() { started = true; } async stop() { stopped = true; }
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
    await commands.get('manuscript.debug')();
    assert.equal(debugConfig.type, 'manuscript');
    assert.equal(debugConfig.program, path.join(root, 'ms.toml'));
    assert.equal(debugConfig.compilerPath, '/compiler path/ms');
    await commands.get('manuscript.profile')();
    assert.deepEqual(terminals[0].shellArgs, ['run', path.join(root, 'ms.toml'), '--cpu-profile', path.join(root, 'CPU profile.pprof')]);
    vscode.workspace.isTrusted = false;
    await commands.get('manuscript.debug')();
    await commands.get('manuscript.profile')();
    assert.equal(builds.length, 0); assert.equal(terminals.length, 1); assert.equal(errors.length, 2);
    await extension.deactivate(); assert.equal(stopped, true);
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});

test('extension declares Manuscript breakpoint support', () => {
  const manifest = require('../package.json');
  assert.deepEqual(manifest.contributes.breakpoints, [{ language: 'manuscript' }]);
});


test('debug launch activates the adapter without an open Manuscript editor', () => {
  const manifest = require('../package.json');
  assert.ok(manifest.activationEvents.includes('onDebugResolve:manuscript'));
  assert.ok(manifest.activationEvents.includes('onDebugInitialConfigurations:manuscript'));
});
