const vscode = require('vscode');
const { LanguageClient } = require('vscode-languageclient/node');
const path = require('node:path');
const { targetFor } = require('./project-target');
let stopClient;
const documentSelector = [
  { scheme: 'file', language: 'manuscript' },
  { scheme: 'manuscript-stdlib', language: 'manuscript' },
];

async function activate(context) {
  const output = vscode.window.createOutputChannel('Manuscript', { log: true });
  const watcher = vscode.workspace.createFileSystemWatcher('{**/*.ms,**/ms.toml}');
  context.subscriptions.push(output, watcher);
  const serverPath = () => vscode.workspace.getConfiguration('manuscript').get('serverPath', 'ms');
  let command = serverPath();
  const makeClient = () => new LanguageClient('manuscript', 'Manuscript', { command, args: ['lsp'] }, {
    documentSelector, synchronize: { fileEvents: watcher }, outputChannel: output,
  });
  let client = makeClient();
  let startup, restarting, shutdown, shuttingDown = false;
  const stopCurrent = async () => {
    const previous = client;
    client = undefined;
    // Failed starts can reject stop(); keep recovery and shutdown available.
    if (previous) try { await previous.stop(); } catch (error) { output.appendLine(error.message); }
  };
  stopClient = () => {
    shuttingDown = true;
    return shutdown ??= (async () => {
      await startup?.catch(() => {});
      await restarting;
      await stopCurrent();
    })();
  };
  context.subscriptions.push(vscode.workspace.registerTextDocumentContentProvider('manuscript-stdlib', {
    async provideTextDocumentContent(uri, token) {
      if (token?.isCancellationRequested) return;
      await (restarting || startup?.catch(() => {}));
      if (shuttingDown || !client || token?.isCancellationRequested) return;
      return client.sendRequest('manuscript/standardLibrarySource', { textDocument: { uri: uri.toString() } }, token);
    },
  }));
  async function savedEditor() {
    if (!vscode.workspace.isTrusted) {
      vscode.window.showErrorMessage('Trust this workspace before running Manuscript code.');
      return;
    }
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'manuscript') return;
    if (!await editor.document.save()) return;
    return editor;
  }
  context.subscriptions.push(vscode.debug.registerDebugAdapterDescriptorFactory('manuscript', {
    createDebugAdapterDescriptor() {
      return new vscode.DebugAdapterExecutable(process.execPath,
        [path.join(context.extensionPath, 'dist/debug-adapter.js'), command],
        { env: { ELECTRON_RUN_AS_NODE: '1' } });
    },
  }));
  context.subscriptions.push(vscode.debug.registerDebugConfigurationProvider('manuscript', {
    async resolveDebugConfiguration(folder, config) {
      if (!vscode.workspace.isTrusted) { vscode.window.showErrorMessage('Trust this workspace before running Manuscript code.'); return; }
      if (!await vscode.workspace.saveAll()) return;
      const editor = vscode.window.activeTextEditor;
      return { type: 'manuscript', name: 'Manuscript', request: 'launch',
        program: editor?.document.uri.fsPath, ...config };
    },
  }));
  context.subscriptions.push(vscode.commands.registerCommand('manuscript.debug', async () => {
    const editor = await savedEditor();
    if (!editor) return;
    try {
      const target = await targetFor(editor.document.uri.fsPath);
      await vscode.debug.startDebugging(vscode.workspace.getWorkspaceFolder(editor.document.uri), {
        type: 'manuscript', name: 'Manuscript', request: 'launch', program: target,
        compilerPath: command, cwd: path.dirname(target),
      });
    } catch (error) { vscode.window.showErrorMessage(`Manuscript debug failed: ${error.message}`); }
  }));
  const restartServer = () => {
    if (shuttingDown) return Promise.resolve();
    if (restarting) return restarting;
    restarting = (async () => {
      await startup.catch(() => {});
      do {
        await stopCurrent();
        if (shuttingDown) return;
        try { command = serverPath(); client = makeClient(); await client.start(); }
        catch (error) { await stopCurrent(); output.appendLine(error.message); output.show(); }
      } while (!shuttingDown && serverPath() !== command);
    })().finally(() => { restarting = undefined; });
    return restarting;
  };
  context.subscriptions.push(vscode.commands.registerCommand('manuscript.restartServer', restartServer));
  if (vscode.workspace.onDidChangeConfiguration) context.subscriptions.push(vscode.workspace.onDidChangeConfiguration((event) => {
    if (event.affectsConfiguration('manuscript.serverPath') && serverPath() !== command) restartServer();
  }));
  if (vscode.tasks) context.subscriptions.push(vscode.tasks.registerTaskProvider('manuscript', {
    async provideTasks(token) {
      if (token?.isCancellationRequested) return [];
      const manifests = await vscode.workspace.findFiles('**/ms.toml', '**/{node_modules,.git}/**', undefined, token);
      if (token?.isCancellationRequested) return [];
      const tasks = [];
      for (const manifest of manifests) for (const operation of ['check', 'build', 'test', 'lint']) {
        if (token?.isCancellationRequested) return [];
        const folder = vscode.workspace.getWorkspaceFolder(manifest);
        const definition = { type: 'manuscript', command: operation, project: manifest.fsPath };
        const task = new vscode.Task(definition, folder, `${operation}: ${path.basename(path.dirname(manifest.fsPath))}`, 'Manuscript',
          new vscode.ProcessExecution(command, [operation, manifest.fsPath], { cwd: path.dirname(manifest.fsPath) }), ['$manuscript']);
        if (operation === 'build') task.group = vscode.TaskGroup.Build;
        if (operation === 'test') task.group = vscode.TaskGroup.Test;
        tasks.push(task);
      }
      return tasks;
    },
    resolveTask(task) {
      const definition = task.definition;
      if (!['check', 'build', 'test', 'lint', 'fmt'].includes(definition.command) || !definition.project) return;
      const args = [definition.command, definition.project]; if (definition.command === 'fmt') args.push('--check');
      return new vscode.Task(definition, task.scope, task.name, 'Manuscript', new vscode.ProcessExecution(command, args), ['$manuscript']);
    },
  }));
  context.subscriptions.push(vscode.commands.registerCommand('manuscript.profile', async () => {
    const editor = await savedEditor();
    if (!editor) return;
    const selected = vscode.window.showQuickPick ? await vscode.window.showQuickPick(['CPU profile', 'Heap profile', 'Execution trace'], { title: 'Choose profiler' }) : 'CPU profile';
    if (!selected) return;
    const flag = { 'CPU profile': '--cpu-profile', 'Heap profile': '--heap-profile', 'Execution trace': '--trace' }[selected];
    const extension = selected === 'Execution trace' ? 'out' : 'pprof';
    const destination = await vscode.window.showSaveDialog({ title: `Save ${selected.toLowerCase()} (choose a new file)`, filters: { [selected]: [extension] } });
    if (!destination) return;
    try {
      const target = await targetFor(editor.document.uri.fsPath);
      const terminal = vscode.window.createTerminal({
        name: `Manuscript ${selected.toLowerCase()}`, shellPath: command,
        shellArgs: ['run', target, flag, destination.fsPath], cwd: path.dirname(target),
      });
      terminal.show();
    } catch (error) { vscode.window.showErrorMessage(error.message); }
  }));
  startup = client.start().catch(async (error) => { await stopCurrent(); throw error; });
  await startup;
}
async function deactivate() { await stopClient?.(); }
module.exports = { activate, deactivate };
