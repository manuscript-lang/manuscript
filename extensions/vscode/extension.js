const vscode = require('vscode');
const { LanguageClient } = require('vscode-languageclient/node');
const fs = require('node:fs/promises');
const path = require('node:path');
let client;

async function targetFor(file) {
  for (let dir = path.dirname(file); ; dir = path.dirname(dir)) {
    const manifest = path.join(dir, 'ms.toml');
    try { await fs.access(manifest); return manifest; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (path.dirname(dir) === dir) return file;
  }
}

async function activate(context) {
  const output = vscode.window.createOutputChannel('Manuscript');
  const watcher = vscode.workspace.createFileSystemWatcher('**/*.{ms,toml}');
  context.subscriptions.push(output, watcher);
  let command = vscode.workspace.getConfiguration('manuscript').get('serverPath', 'ms');
  client = new LanguageClient('manuscript', 'Manuscript', { command, args: ['lsp'] }, {
    documentSelector: [{ scheme: 'file', language: 'manuscript' }],
    synchronize: { fileEvents: watcher }, outputChannel: output,
  });
  context.subscriptions.push(vscode.workspace.registerTextDocumentContentProvider('manuscript-stdlib', {
    provideTextDocumentContent(uri) {
      return client.sendRequest('manuscript/standardLibrarySource', { textDocument: { uri: uri.toString() } });
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
  let delve = vscode.workspace.getConfiguration('manuscript').get('delvePath', 'dlv');
  context.subscriptions.push(vscode.debug.registerDebugAdapterDescriptorFactory('manuscript', {
    createDebugAdapterDescriptor() {
      return new vscode.DebugAdapterExecutable(process.execPath,
        [path.join(context.extensionPath, 'dist/debug-adapter.js'), command, delve],
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
        compilerPath: command, delvePath: delve, cwd: path.dirname(target),
      });
    } catch (error) { vscode.window.showErrorMessage(`Manuscript debug failed: ${error.message}`); }
  }));
  context.subscriptions.push(vscode.commands.registerCommand('manuscript.restartServer', async () => {
    try { await client.stop(); command = vscode.workspace.getConfiguration('manuscript').get('serverPath', 'ms');
      delve = vscode.workspace.getConfiguration('manuscript').get('delvePath', 'dlv');
      client = new LanguageClient('manuscript', 'Manuscript', { command, args: ['lsp'] }, {
        documentSelector: [{ scheme: 'file', language: 'manuscript' }], synchronize: { fileEvents: watcher }, outputChannel: output,
      }); await client.start();
    } catch (error) { output.appendLine(error.message); output.show(); }
  }));
  if (vscode.tasks) context.subscriptions.push(vscode.tasks.registerTaskProvider('manuscript', {
    async provideTasks() {
      const manifests = await vscode.workspace.findFiles('**/ms.toml', '**/{node_modules,.git}/**');
      const tasks = [];
      for (const manifest of manifests) for (const operation of ['check', 'build', 'test', 'lint']) {
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
  await client.start();
}
async function deactivate() { if (client) await client.stop(); }
module.exports = { activate, deactivate };
