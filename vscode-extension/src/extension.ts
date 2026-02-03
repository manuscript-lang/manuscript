import * as path from "path";
import * as vscode from "vscode";
import type { ExtensionContext } from "vscode";
import {
  LanguageClient,
  type LanguageClientOptions,
  type ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

// Import embedded stdlib source
import { stdlibSource } from "../../src/stdlib";

let client: LanguageClient;

// Virtual document provider for stdlib (read-only)
class StdlibContentProvider implements vscode.TextDocumentContentProvider {
  provideTextDocumentContent(_uri: vscode.Uri): string {
    return stdlibSource;
  }
}

export function activate(context: ExtensionContext) {
  // Register content provider for manuscript:// scheme (stdlib virtual documents)
  const provider = new StdlibContentProvider();
  context.subscriptions.push(
    vscode.workspace.registerTextDocumentContentProvider("manuscript", provider)
  );

  // Set language mode for stdlib virtual documents
  context.subscriptions.push(
    vscode.workspace.onDidOpenTextDocument(async (doc) => {
      if (doc.uri.scheme === "manuscript" && doc.languageId !== "manuscript") {
        await vscode.languages.setTextDocumentLanguage(doc, "manuscript");
      }
    })
  );

  const serverModule = context.asAbsolutePath(path.join("out", "server.js"));

  const serverOptions: ServerOptions = {
    run: { module: serverModule, transport: TransportKind.ipc },
    debug: {
      module: serverModule,
      transport: TransportKind.ipc,
      options: { execArgv: ["--nolazy", "--inspect=6009"] },
    },
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: "file", language: "manuscript" },
      { scheme: "manuscript", language: "manuscript" }, // Support stdlib virtual documents
    ],
    synchronize: {
      fileEvents: undefined,
    },
  };

  client = new LanguageClient(
    "manuscriptLanguageServer",
    "Manuscript Language Server",
    serverOptions,
    clientOptions
  );

  client.start();
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) {
    return undefined;
  }
  return client.stop();
}
