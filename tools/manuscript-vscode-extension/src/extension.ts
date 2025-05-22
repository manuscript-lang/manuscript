import * as path from 'path';
import * as vscode from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    TransportKind
} from 'vscode-languageclient/node';

let client: LanguageClient;

export function activate(context: vscode.ExtensionContext) {
    const command = context.asAbsolutePath(
        'msc-lsp'
    );
    // If the extension is launched in debug mode then the debug server options are used
    // Otherwise the run options are used
    const serverOptions: ServerOptions = {
        run: { command: command, transport: TransportKind.stdio },
        debug: {
            command: command,
            transport: TransportKind.stdio,
            args: ["--debug"] // Optional: example of passing debug args to Go LSP
            // options: { env: { ...process.env, "LSP_DEBUG": "true" } } // Alternative way to signal debug
        }
    };

    // Options to control the language client (documentSelector remains the same)
    const clientOptions: LanguageClientOptions = {
        documentSelector: [{ scheme: 'file', language: 'manuscript' }],
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/.clientrc') // Or other relevant files
        }
    };

    // Create the language client and start the client.
    client = new LanguageClient(
        'manuscriptLanguageServer',
        'Manuscript Language Server (Go)', // Updated display name
        serverOptions,
        clientOptions
    );

    // Start the client. This will also launch the server
    client.start().then(() => {
        vscode.window.showInformationMessage('Manuscript Language Server (Go) started successfully!');
    }).catch(error => {
        vscode.window.showErrorMessage(`Failed to start Manuscript Language Server (Go): ${error}. Ensure Go LSP executable is built and at the correct path: ${command}`);
    });

    console.log('Manuscript extension activated. Attempting to start Go Language client.');
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    console.log('Manuscript extension deactivating. Stopping Go language client.');
    return client.stop();
}
