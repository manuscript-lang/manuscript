// Manuscript Language Server — thin LSP protocol adapter over LanguageService
import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  type InitializeParams,
  TextDocumentSyncKind,
  type InitializeResult,
  Diagnostic,
  DiagnosticSeverity,
  CompletionItem,
  CompletionItemKind,
  Hover,
  MarkupKind,
  Position,
  DocumentSymbol,
  SymbolKind,
  type Definition,
  Location,
  Range,
  WorkspaceEdit,
} from "vscode-languageserver/node";
import { TextDocument } from "vscode-languageserver-textdocument";

import {
  LanguageService,
  type LanguageServiceHost,
  type DiagnosticInfo,
  type CompletionItemData,
  type CompletionInfo,
  type DocumentSymbolKind,
} from "../../src/lsp";

import * as path from "path";
import * as fs from "fs/promises";
import { fileURLToPath } from "node:url";
import { getProjectConfig } from "./project";

// ============================================
// Host Implementation
// ============================================

const host: LanguageServiceHost = {
  readFile: (p) => fs.readFile(path.resolve(p), "utf-8"),
  async listMsFiles(dir: string): Promise<string[]> {
    const out: string[] = [];
    async function walk(d: string): Promise<void> {
      let entries: { name: string; isFile: () => boolean }[];
      try {
        entries = await fs.readdir(d, { withFileTypes: true });
      } catch {
        return;
      }
      for (const e of entries) {
        const full = path.join(d, e.name);
        if (e.isFile()) {
          if (e.name.toLowerCase().endsWith(".ms")) out.push(full);
        } else {
          await walk(full);
        }
      }
    }
    await walk(path.resolve(dir));
    return out;
  },
  getProjectConfig: (filePath) => getProjectConfig(filePath),
};

// ============================================
// Server Setup
// ============================================

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const service = new LanguageService(host);

connection.onInitialize((_params: InitializeParams): InitializeResult => ({
  capabilities: {
    textDocumentSync: TextDocumentSyncKind.Incremental,
    completionProvider: { triggerCharacters: [".", ":"], resolveProvider: true },
    hoverProvider: true,
    documentSymbolProvider: true,
    definitionProvider: true,
    referencesProvider: true,
    renameProvider: { prepareProvider: true },
  },
}));

// ============================================
// Document Validation
// ============================================

documents.onDidChangeContent(e => validateDocument(e.document));

async function validateDocument(doc: TextDocument): Promise<void> {
  const diagnostics = await service.validateDocument(doc.uri, doc.getText());
  connection.sendDiagnostics({
    uri: doc.uri,
    diagnostics: diagnostics.map(toDiagnostic),
  });
}

function toDiagnostic(d: DiagnosticInfo): Diagnostic {
  return {
    severity: d.severity === "error" ? DiagnosticSeverity.Error : DiagnosticSeverity.Warning,
    range: {
      start: { line: d.line - 1, character: d.col - 1 },
      end: { line: d.line - 1, character: d.endCol - 1 },
    },
    message: d.message,
    source: "manuscript",
  };
}

// ============================================
// Completions
// ============================================

connection.onCompletion((params): CompletionItem[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];

  const lineText = doc.getText({
    start: { line: params.position.line, character: 0 },
    end: params.position,
  });
  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character;

  const infos = service.getCompletions(params.textDocument.uri, oneBasedLine, oneBasedCol, lineText);
  return infos.map(i => ({
    label: i.label,
    kind: completionKindMap[i.kind],
    detail: i.detail,
    documentation: i.doc,
    data: (i as any).data,
  }));
});

connection.onCompletionResolve(async (item): Promise<CompletionItem> => {
  const data = item.data as CompletionItemData | undefined;
  if (!data) return item;

  const result = await service.resolveCompletion({ label: item.label, kind: "variable", data });
  if (result.detail) item.detail = result.detail;
  if (result.doc) item.documentation = { kind: MarkupKind.Markdown, value: result.doc };
  return item;
});

// ============================================
// Hover
// ============================================

connection.onHover(async (params): Promise<Hover | null> => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const { word, isProperty } = getWord(doc, params.position);
  if (!word) return null;

  const result = await service.getHover(
    params.textDocument.uri,
    params.position.line + 1,
    params.position.character + 1,
    word,
    isProperty
  );
  if (!result) return null;
  return hover(result.signature, result.doc);
});

// ============================================
// Document Symbols
// ============================================

connection.onDocumentSymbol((params): DocumentSymbol[] => {
  const symbols = service.getDocumentSymbols(params.textDocument.uri);
  return symbols.map(s => ({
    name: s.name,
    kind: documentSymbolKindMap[s.kind],
    range: locToRange(s.loc),
    selectionRange: locToRange(s.loc),
  }));
});

// ============================================
// Go to Definition
// ============================================

connection.onDefinition(async (params): Promise<Definition | null> => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const { word } = getWord(doc, params.position);
  if (!word) return null;

  const result = await service.getDefinition(
    params.textDocument.uri,
    params.position.line + 1,
    params.position.character + 1,
    word
  );
  if (!result) return null;
  return Location.create(result.uri, {
    start: { line: result.line - 1, character: result.col - 1 },
    end: { line: result.line - 1, character: result.col - 1 + result.length },
  });
});

// ============================================
// Find References
// ============================================

connection.onReferences(async (params): Promise<Location[]> => {
  const locations = await service.getReferences(
    params.textDocument.uri,
    params.position.line + 1,
    params.position.character + 1
  );
  return locations.map(loc =>
    Location.create(loc.uri, {
      start: { line: loc.line - 1, character: loc.col - 1 },
      end: { line: loc.line - 1, character: loc.col - 1 + loc.length },
    })
  );
});

// ============================================
// Rename
// ============================================

connection.onPrepareRename((params): Range | null => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const { word, start } = getWord(doc, params.position);
  if (!word) return null;
  if (!service.canRename(word)) return null;

  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character + 1;
  if (!service.hasDefinitionAt(params.textDocument.uri, oneBasedLine, oneBasedCol)) return null;

  return {
    start: { line: params.position.line, character: start },
    end: { line: params.position.line, character: start + word.length },
  };
});

connection.onRenameRequest((params): WorkspaceEdit | null => {
  const locations = service.getRenameLocations(
    params.textDocument.uri,
    params.position.line + 1,
    params.position.character + 1
  );
  if (!locations) return null;

  const ranges = locations.map(loc => ({
    start: { line: loc.line - 1, character: loc.col - 1 },
    end: { line: loc.line - 1, character: loc.col - 1 + loc.length },
  }));
  return {
    changes: {
      [params.textDocument.uri]: ranges.map(r => ({ range: r, newText: params.newName })),
    },
  };
});

// ============================================
// Helpers (protocol-specific)
// ============================================

function getWord(doc: TextDocument, pos: Position): { word: string; isProperty: boolean; start: number } {
  const line = doc.getText({ start: { line: pos.line, character: 0 }, end: { line: pos.line + 1, character: 0 } });
  const before = line.slice(0, pos.character);
  const after = line.slice(pos.character);
  const wordStart = before.match(/[a-zA-Z_][a-zA-Z0-9_]*$/)?.[0] || "";
  const wordEnd = after.match(/^[a-zA-Z0-9_]*/)?.[0] || "";
  const word = wordStart + wordEnd;
  const beforeWord = before.slice(0, before.length - wordStart.length);
  return { word, isProperty: beforeWord.trimEnd().endsWith("."), start: pos.character - wordStart.length };
}

function hover(signature: string, doc?: string): Hover {
  const codeBlock = "```manuscript\n" + signature + "\n```";
  const value = doc ? `${codeBlock}\n\n${doc}` : codeBlock;
  return { contents: { kind: MarkupKind.Markdown, value } };
}

function locToRange(loc: { line: number; column: number }, length = 1): Range {
  return {
    start: { line: loc.line - 1, character: loc.column - 1 },
    end: { line: loc.line - 1, character: loc.column - 1 + length },
  };
}

const completionKindMap: Record<CompletionInfo["kind"], CompletionItemKind> = {
  function: CompletionItemKind.Function,
  type: CompletionItemKind.Class,
  variable: CompletionItemKind.Variable,
  property: CompletionItemKind.Property,
  method: CompletionItemKind.Method,
  keyword: CompletionItemKind.Keyword,
};

const documentSymbolKindMap: Record<DocumentSymbolKind, SymbolKind> = {
  function: SymbolKind.Function,
  type: SymbolKind.Class,
  variable: SymbolKind.Variable,
  parameter: SymbolKind.Variable,
  field: SymbolKind.Property,
  method: SymbolKind.Method,
  import: SymbolKind.Variable,
};

// ============================================
// Start Server
// ============================================

documents.listen(connection);
connection.listen();
