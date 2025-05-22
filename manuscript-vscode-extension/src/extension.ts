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
    // Path to the Go LSP server executable
    // IMPORTANT: This path assumes the Go executable will be built to a location
    // relative to the extension's runtime 'out' directory.
    // If 'lsp' is a top-level directory sibling to 'manuscript-vscode-extension',
    // and the Go binary is in 'lsp/bin/manuscript-lsp':
    const command = context.asAbsolutePath(
        path.join(context.extensionPath, '..', 'lsp', 'bin', 'manuscript-lsp') 
    );
    // If the binary were, for example, packaged inside the extension in a 'bin' folder:
    // const command = context.asAbsolutePath(path.join(context.extensionPath, 'bin', 'manuscript-lsp'));


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
