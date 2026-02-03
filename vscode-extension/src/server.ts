// Manuscript Language Server - Thin LSP wrapper over language capabilities
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

// Language capabilities from src/
import { Parser } from "../../src/parser";
import { TypeChecker } from "../../src/types/checker";
import { KEYWORDS } from "../../src/lexer/tokens";
import { STDLIB_FUNCTIONS, isBuiltin } from "../../src/shared/stdlib";
import { stdlibSource, STDLIB_PATH_URI } from "../../src/stdlib";

// AST traversal
import { visit } from "../../src/types/ast-visitor";

// Type utilities (for completions)
import {
  formatFnSignature,
  formatTypeSignature,
  getDocstring,
} from "../../src/types/type-utils";

// Stdlib extraction
import {
  collectStdlibSymbols,
  collectTypeMembersFromProgram,
  type StdlibSymbol,
  type TypeMemberInfo,
} from "../../src/stdlib/extractor";

// LSP-specific symbol resolution
import {
  SymbolTable,
  buildSymbolTable,
  resolveDefinition,
  findReferences,
  getRenameLocations,
  getHoverForSymbol,
  getDocumentSymbols,
  getTypeMemberCompletions,
  getObjectMemberCompletions,
  resolveObjectType,
  type DocumentSymbolKind,
  type CompletionInfo,
} from "../../src/lsp";

import type { Program, FnDecl, TypeDecl, ASTNode, Expr } from "../../src/parser/ast";
import * as AST from "../../src/parser/ast";
import type { Type } from "../../src/types/types";
import type { TypeEnvironment } from "../../src/types/environment";

// ============================================
// Server State
// ============================================

interface CachedDocument {
  program: Program;
  types: Map<ASTNode, Type>;
  env: TypeEnvironment;
  symbols: SymbolTable;
}

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const cache = new Map<string, CachedDocument>();

// Parse stdlib once on startup
const stdlibProgram = new Parser(stdlibSource).parse();
const stdlibSymbols = collectStdlibSymbols(stdlibProgram);
const stdlibTypeMembers = collectTypeMembersFromProgram(stdlibProgram);

// Derived constants
const KEYWORD_LIST = Object.keys(KEYWORDS);
const BUILTIN_PRIMITIVE_TYPES = ["number", "string", "bool", "null", "bytes", "any", "never", "void"];

// ============================================
// LSP Initialization
// ============================================

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
  const diagnostics: Diagnostic[] = [];

  if (doc.uri === STDLIB_PATH_URI) {
    connection.sendDiagnostics({ uri: doc.uri, diagnostics: [] });
    return;
  }

  try {
    const program = new Parser(doc.getText()).parse();
    const result = new TypeChecker().check(program);
    const symbols = buildSymbolTable(program, result.types, result.env);
    cache.set(doc.uri, { program, types: result.types, env: result.env, symbols });

    for (const err of result.errors) {
      diagnostics.push({
        severity: DiagnosticSeverity.Error,
        range: {
          start: { line: err.loc.line - 1, character: err.loc.column - 1 },
          end: { line: err.loc.line - 1, character: err.loc.column + 10 },
        },
        message: err.message.replace(/ at line \d+, column \d+$/, ""),
        source: "manuscript",
      });
    }
    for (const w of result.warnings) {
      diagnostics.push({
        severity: DiagnosticSeverity.Warning,
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
        message: w,
        source: "manuscript",
      });
    }
  } catch (e: any) {
    const m = e.message?.match(/at line (\d+), column (\d+)/);
    diagnostics.push({
      severity: DiagnosticSeverity.Error,
      range: {
        start: { line: m ? +m[1] - 1 : 0, character: m ? +m[2] - 1 : 0 },
        end: { line: m ? +m[1] - 1 : 0, character: (m ? +m[2] : 0) + 1 },
      },
      message: e.message?.replace(/ at line \d+, column \d+$/, "") || "Parse error",
      source: "manuscript",
    });
  }

  connection.sendDiagnostics({ uri: doc.uri, diagnostics });
}

// ============================================
// Completions
// ============================================

connection.onCompletion((params): CompletionItem[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];

  const line = doc.getText({ start: { line: params.position.line, character: 0 }, end: params.position });
  const cached = cache.get(params.textDocument.uri);

  // After colon: type completions
  if (line.match(/:\s*$/)) {
    const items: CompletionItem[] = BUILTIN_PRIMITIVE_TYPES.map(t => ({ label: t, kind: CompletionItemKind.TypeParameter }));
    for (const [name, sym] of stdlibSymbols) {
      if (sym.kind === "type") items.push({ label: name, kind: CompletionItemKind.Class });
    }
    if (cached) {
      for (const s of cached.program.body) {
        if (s.kind === "TypeDecl") items.push({ label: s.name, kind: CompletionItemKind.Class });
      }
    }
    return items;
  }

  // After dot: member completions
  if (line.match(/\.\s*$/)) {
    if (cached) {
      let bestExpr: Expr | null = null;
      const oneBasedLine = params.position.line + 1;
      const oneBasedCol = params.position.character;
      visit(cached.program, {
        expr(e) {
          if (!e?.loc || e.loc.line !== oneBasedLine) return;
          if (e.loc.column <= oneBasedCol) bestExpr = e;
        },
      });
      const type = bestExpr ? cached.types.get(bestExpr) : undefined;
      if (type) {
        // Try stdlib type members (string, list, map, set)
        const stdlibCompletions = getTypeMemberCompletions(stdlibTypeMembers, type.kind);
        if (stdlibCompletions.length > 0) return toCompletionItems(stdlibCompletions);
        // Try user-defined object types
        const obj = resolveObjectType(cached.program, type);
        if (obj) return toCompletionItems(getObjectMemberCompletions(obj));
      }
    }
    return toCompletionItems(getTypeMemberCompletions(stdlibTypeMembers, "list"));
  }

  // Default: keywords, functions, variables
  const items: CompletionItem[] = [
    ...KEYWORD_LIST.map(k => ({ label: k, kind: CompletionItemKind.Keyword })),
    ...[...STDLIB_FUNCTIONS].map(f => ({ label: f, kind: CompletionItemKind.Function, data: { fn: f } })),
  ];

  if (cached) {
    for (const s of cached.program.body) {
      if (s.kind === "FnDecl") {
        items.push({ label: s.name, kind: CompletionItemKind.Function, data: { uri: params.textDocument.uri, fn: s.name } });
      } else if (s.kind === "TypeDecl") {
        const { signature } = formatTypeSignature(s);
        items.push({ label: s.name, kind: CompletionItemKind.Class, detail: signature, data: { uri: params.textDocument.uri, type: s.name } });
      } else if (s.kind === "LetStmt" || s.kind === "VarStmt") {
        const name = (s as any).name || (s as any).pattern?.name;
        if (name) items.push({ label: name, kind: CompletionItemKind.Variable });
      }
    }
  }

  return items;
});

connection.onCompletionResolve((item): CompletionItem => {
  const data = item.data as { fn?: string; type?: string; uri?: string } | undefined;
  if (!data) return item;

  if (data.fn) {
    const sym = stdlibSymbols.get(data.fn);
    if (sym?.doc) {
      item.documentation = { kind: MarkupKind.Markdown, value: sym.doc };
      return item;
    }
  }

  if (data.uri) {
    const cached = cache.get(data.uri);
    for (const s of cached?.program.body || []) {
      if (data.fn && s.kind === "FnDecl" && s.name === data.fn) {
        item.detail = formatFnSignature(s);
        const doc = getDocstring(s.body);
        if (doc) item.documentation = { kind: MarkupKind.Markdown, value: doc };
        break;
      }
      if (data.type && s.kind === "TypeDecl" && s.name === data.type) {
        const { fields } = formatTypeSignature(s);
        if (fields.length) {
          item.documentation = { kind: MarkupKind.Markdown, value: `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` };
        }
        break;
      }
    }
  }

  return item;
});

// ============================================
// Hover
// ============================================

connection.onHover((params): Hover | null => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return null;

  const { word, isProperty } = getWord(doc, params.position);
  if (!word) return null;

  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character + 1;

  // Try symbol table first for user-defined symbols
  const symbolHover = getHoverForSymbol(cached.symbols, cached.types, cached.program, oneBasedLine, oneBasedCol);
  if (symbolHover) return hover(symbolHover.signature, symbolHover.doc);

  // Property access: check stdlib type members
  if (isProperty) {
    for (const [, members] of stdlibTypeMembers) {
      const member = members.find(m => m.name === word);
      if (member) {
        if (member.kind === "field") {
          return hover(`(field) ${word}: ${member.signature}`, member.doc);
        } else {
          const sig = member.signature.startsWith("fn") ? member.signature.slice(2) : member.signature;
          return hover(`(method) fn ${word}${sig}`, member.doc);
        }
      }
    }
    return null;
  }

  // Check stdlib functions/types
  const stdlibSym = stdlibSymbols.get(word);
  if (stdlibSym?.signature) return hover(stdlibSym.signature, stdlibSym.doc);

  // Keywords and builtins
  if (KEYWORD_LIST.includes(word)) return hover(`(keyword) ${word}`);
  if (BUILTIN_PRIMITIVE_TYPES.includes(word)) return hover(`(type) ${word}`);

  return null;
});

// ============================================
// Document Symbols
// ============================================

connection.onDocumentSymbol((params): DocumentSymbol[] => {
  const cached = cache.get(params.textDocument.uri);
  if (!cached) return [];

  const symbols = getDocumentSymbols(cached.symbols);
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

connection.onDefinition((params): Definition | null => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return null;

  const { word } = getWord(doc, params.position);
  if (!word) return null;

  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character + 1;

  // Use symbol table for resolution
  const def = resolveDefinition(cached.symbols, oneBasedLine, oneBasedCol);
  if (def) {
    const col = def.loc.column - 1 + def.nameOffset;
    return Location.create(params.textDocument.uri, {
      start: { line: def.loc.line - 1, character: col },
      end: { line: def.loc.line - 1, character: col + def.name.length },
    });
  }

  // Check stdlib functions/types
  const stdlibSym = stdlibSymbols.get(word);
  if (stdlibSym) {
    return Location.create(STDLIB_PATH_URI, locToRange(stdlibSym.loc));
  }

  return null;
});

// ============================================
// Find References
// ============================================

connection.onReferences((params): Location[] => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return [];

  const uri = params.textDocument.uri;
  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character + 1;

  // Use symbol table for resolution
  const result = findReferences(cached.symbols, oneBasedLine, oneBasedCol);
  if (!result) return [];

  const locations: Location[] = [];
  
  // Add definition location
  const defCol = result.definition.loc.column - 1 + result.definition.nameOffset;
  locations.push(Location.create(uri, {
    start: { line: result.definition.loc.line - 1, character: defCol },
    end: { line: result.definition.loc.line - 1, character: defCol + result.definition.name.length },
  }));

  // Add all reference locations
  for (const ref of result.references) {
    locations.push(Location.create(uri, locToRange(ref.loc, result.definition.name.length)));
  }

  return locations;
});

// ============================================
// Rename
// ============================================

connection.onPrepareRename((params): Range | null => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return null;

  const { word, start } = getWord(doc, params.position);
  if (!word) return null;
  if (isBuiltin(word) || KEYWORD_LIST.includes(word) || BUILTIN_PRIMITIVE_TYPES.includes(word)) return null;

  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character + 1;
  
  // Check if there's a symbol at this position
  const def = resolveDefinition(cached.symbols, oneBasedLine, oneBasedCol);
  if (!def) return null;

  return { start: { line: params.position.line, character: start }, end: { line: params.position.line, character: start + word.length } };
});

connection.onRenameRequest((params): WorkspaceEdit | null => {
  const cached = cache.get(params.textDocument.uri);
  if (!cached) return null;

  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character + 1;

  const locations = getRenameLocations(cached.symbols, oneBasedLine, oneBasedCol);
  if (!locations || locations.length === 0) return null;

  const ranges = locations.map(loc => locToRange(loc.loc, loc.length));
  return { changes: { [params.textDocument.uri]: ranges.map(r => ({ range: r, newText: params.newName })) } };
});

// ============================================
// Helpers
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

// ============================================
// Completion Helpers (LSP-specific converters)
// ============================================

function toCompletionItems(infos: CompletionInfo[]): CompletionItem[] {
  return infos.map(i => ({
    label: i.label,
    kind: completionKindMap[i.kind],
    detail: i.detail,
    documentation: i.doc,
  }));
}

const documentSymbolKindMap: Record<DocumentSymbolKind, SymbolKind> = {
  function: SymbolKind.Function,
  type: SymbolKind.Class,
  variable: SymbolKind.Variable,
  parameter: SymbolKind.Variable,
  field: SymbolKind.Property,
  method: SymbolKind.Method,
};

const completionKindMap: Record<CompletionInfo["kind"], CompletionItemKind> = {
  function: CompletionItemKind.Function,
  type: CompletionItemKind.Class,
  variable: CompletionItemKind.Variable,
  property: CompletionItemKind.Property,
  method: CompletionItemKind.Method,
  keyword: CompletionItemKind.Keyword,
};

// ============================================
// Start Server
// ============================================

documents.listen(connection);
connection.listen();
