import * as path from "path";
import * as vscode from "vscode";
import type { ExtensionContext } from "vscode";
import {
  LanguageClient,
  type LanguageClientOptions,
  type ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

import { builtinsSource } from "../../src/builtin";

let client: LanguageClient;

class BuiltinsContentProvider implements vscode.TextDocumentContentProvider {
  provideTextDocumentContent(_uri: vscode.Uri): string {
    return builtinsSource;
  }
}

export function activate(context: ExtensionContext) {
  const provider = new BuiltinsContentProvider();
  context.subscriptions.push(
    vscode.workspace.registerTextDocumentContentProvider("manuscript", provider)
  );

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
      { scheme: "manuscript", language: "manuscript" },
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
