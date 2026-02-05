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
  findConstructorCalleeAt,
  type DocumentSymbolKind,
  type CompletionInfo,
  type HoverInfo,
} from "../../src/lsp";

import type { Program, FnDecl, TypeDecl, ASTNode, Expr } from "../../src/parser/ast";
import * as AST from "../../src/parser/ast";
import type { TypeEnvironment } from "../../src/types/environment";
import * as path from "path";
import * as fs from "fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { typecheckDocumentInProject } from "../../src/cli/compiler";
import { findMsToml, loadMsToml, resolveSpecifier } from "../../src/modules";

// ============================================
// Server State
// ============================================

interface CachedDocument {
  program: Program;
  env: TypeEnvironment;
  symbols: SymbolTable;
}

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const cache = new Map<string, CachedDocument>();

async function getOrLoadCached(depPath: string): Promise<CachedDocument | null> {
  const uri = pathToFileURL(path.resolve(depPath)).href;
  const existing = cache.get(uri);
  if (existing) return existing;
  let content: string;
  try {
    content = await fs.readFile(path.resolve(depPath), "utf-8");
  } catch {
    return null;
  }
  const result = await typecheckDocumentInProject(depPath, content, (p) =>
    fs.readFile(path.resolve(p), "utf-8")
  );
  if (!result) {
    try {
      const program = new Parser(content).parse();
      const checkResult = new TypeChecker().check(program);
      const symbols = buildSymbolTable(program, checkResult.env);
      const cached: CachedDocument = { program, env: checkResult.env, symbols };
      cache.set(uri, cached);
      return cached;
    } catch {
      return null;
    }
  }
  const symbols = buildSymbolTable(result.program, result.env);
  const cached: CachedDocument = { program: result.program, env: result.env, symbols };
  cache.set(uri, cached);
  return cached;
}

async function listMsFilesInDir(dir: string): Promise<string[]> {
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
}

/** Resolve project config from a file URI. Returns null if no project. */
async function getProjectConfig(
  fileUri: string
): Promise<{ projectRoot: string; config: Awaited<ReturnType<typeof loadMsToml>> } | null> {
  const entryPath = fileURLToPath(new URL(fileUri));
  const projectRoot = await findMsToml(path.dirname(entryPath));
  if (!projectRoot) return null;
  try {
    const config = await loadMsToml(projectRoot);
    return { projectRoot, config };
  } catch {
    return null;
  }
}

/** Specifier for a file path relative to srcDir (e.g. "src/ms/add" for add.ms). */
function specifierForFile(srcDir: string, filePath: string): string {
  const rel = path.relative(srcDir, path.resolve(filePath));
  return rel.replace(/\.ms$/i, "").replace(/\\/g, "/");
}

// Parse stdlib once on startup (comments are captured in AST during parsing)
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

  if (doc.uri.startsWith("file:")) {
    const entryPath = fileURLToPath(new URL(doc.uri));
    const projectResult = await typecheckDocumentInProject(
      entryPath,
      doc.getText(),
      (p) => fs.readFile(path.resolve(p), "utf-8")
    );
    if (projectResult) {
      const { program, env, errors, warnings } = projectResult;
      const symbols = buildSymbolTable(program, env);
      cache.set(doc.uri, { program, env, symbols });
      const entryAbs = path.resolve(entryPath);
      for (const err of errors) {
        if (err.file && path.resolve(err.file) === entryAbs) {
          diagnostics.push({
            severity: DiagnosticSeverity.Error,
            range: {
              start: { line: (err.line ?? 1) - 1, character: (err.column ?? 1) - 1 },
              end: { line: (err.line ?? 1) - 1, character: (err.column ?? 1) + 10 },
            },
            message: err.message.replace(/ at line \d+, column \d+$/, ""),
            source: "manuscript",
          });
        }
      }
      for (const w of warnings) {
        if (w.file && path.resolve(w.file) === entryAbs) {
          diagnostics.push({
            severity: DiagnosticSeverity.Warning,
            range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
            message: w.message,
            source: "manuscript",
          });
        }
      }
      connection.sendDiagnostics({ uri: doc.uri, diagnostics });
      return;
    }
  }

  try {
    const program = new Parser(doc.getText()).parse();
    const result = new TypeChecker().check(program);
    const symbols = buildSymbolTable(program, result.env);
    cache.set(doc.uri, { program, env: result.env, symbols });

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
      const type = bestExpr?.resolvedType;
      if (type) {
        // Try stdlib type members (string, list, map, set)
        const stdlibCompletions = getTypeMemberCompletions(stdlibTypeMembers, type.kind);
        if (stdlibCompletions.length > 0) return toCompletionItems(stdlibCompletions);
        // Try user-defined object types
        const obj = resolveObjectType(cached.program, type, cached.env);
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
      } else if (s.kind === "ImportDecl") {
        for (const { name, alias } of s.names) {
          const label = alias ?? name;
          items.push({
            label,
            kind: CompletionItemKind.Function,
            data: { import: true, specifier: s.source, exportedName: name, uri: params.textDocument.uri },
          });
        }
      }
    }
  }

  return items;
});

connection.onCompletionResolve(async (item): Promise<CompletionItem> => {
  const data = item.data as {
    fn?: string;
    type?: string;
    uri?: string;
    import?: boolean;
    specifier?: string;
    exportedName?: string;
  } | undefined;
  if (!data) return item;

  if (data.import && data.specifier != null && data.exportedName != null && data.uri) {
    const proj = await getProjectConfig(data.uri);
    if (proj) {
      const resolved = resolveSpecifier(proj.projectRoot, proj.config.srcDir, data.specifier);
      if ("kind" in resolved && resolved.kind === "local") {
        const depCached = await getOrLoadCached(resolved.path);
        if (depCached) {
          for (const s of depCached.program.body) {
            if (s.kind === "FnDecl" && s.name === data.exportedName) {
              item.detail = formatFnSignature(s);
              if (s.doc) item.documentation = { kind: MarkupKind.Markdown, value: s.doc };
              return item;
            }
            if (s.kind === "TypeDecl" && s.name === data.exportedName) {
              const { signature, fields } = formatTypeSignature(s);
              item.detail = signature;
              const doc = s.doc ?? (fields.length ? `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` : undefined);
              if (doc) item.documentation = { kind: MarkupKind.Markdown, value: doc };
              return item;
            }
          }
        }
      }
    }
    return item;
  }

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
        if (s.doc) item.documentation = { kind: MarkupKind.Markdown, value: s.doc };
        break;
      }
      if (data.type && s.kind === "TypeDecl" && s.name === data.type) {
        const { fields } = formatTypeSignature(s);
        const doc = s.doc ?? (fields.length ? `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` : undefined);
        if (doc) item.documentation = { kind: MarkupKind.Markdown, value: doc };
        break;
      }
    }
  }

  return item;
});

// ============================================
// Hover
// ============================================

connection.onHover(async (params): Promise<Hover | null> => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return null;

  const { word, isProperty } = getWord(doc, params.position);
  if (!word) return null;

  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character + 1;

  let symbolHover = getHoverForSymbol(cached.symbols, cached.program, oneBasedLine, oneBasedCol, cached.env);
  if (!symbolHover) {
    const def = resolveDefinition(cached.symbols, oneBasedLine, oneBasedCol);
    const importTarget = def?.importTarget ?? getImportBindingOnLine(cached.program, oneBasedLine, word);
    if (importTarget) {
      symbolHover = await resolveImportHover(doc.uri, importTarget);
    }
  }
  if (symbolHover) return hover(symbolHover.signature, symbolHover.doc);

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

connection.onDefinition(async (params): Promise<Definition | null> => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return null;

  const { word } = getWord(doc, params.position);
  if (!word) return null;

  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character + 1;

  let def = resolveDefinition(cached.symbols, oneBasedLine, oneBasedCol);
  if (def) {
    if (def.importTarget) {
      const depLocation = await resolveImportDefinition(doc.uri, def.importTarget);
      if (depLocation) return depLocation;
    }
    if (def.id.kind === "type") {
      const ctorCallee = findConstructorCalleeAt(cached.program, oneBasedLine, oneBasedCol);
      if (ctorCallee === def.name) {
        const initDef = cached.symbols.getDefinition(`${def.name}.init`);
        if (initDef) def = initDef;
      }
    }
    const col = def.loc.column - 1 + def.nameOffset;
    return Location.create(params.textDocument.uri, {
      start: { line: def.loc.line - 1, character: col },
      end: { line: def.loc.line - 1, character: col + def.name.length },
    });
  }

  const importTarget = getImportBindingOnLine(cached.program, oneBasedLine, word);
  if (importTarget) {
    const depLocation = await resolveImportDefinition(doc.uri, importTarget);
    if (depLocation) return depLocation;
  }

  const stdlibSym = stdlibSymbols.get(word);
  if (stdlibSym) {
    return Location.create(STDLIB_PATH_URI, locToRange(stdlibSym.loc));
  }

  return null;
});

function getImportBindingOnLine(
  program: AST.Program,
  line: number,
  word: string
): { specifier: string; exportedName: string } | null {
  for (const stmt of program.body) {
    if (stmt.kind !== "ImportDecl" || stmt.loc?.line !== line) continue;
    for (const { name, alias } of stmt.names) {
      if ((alias ?? name) === word) return { specifier: stmt.source, exportedName: name };
    }
  }
  return null;
}

async function resolveImportDefinition(
  currentUri: string,
  importTarget: { specifier: string; exportedName: string }
): Promise<Location | null> {
  const entryPath = fileURLToPath(new URL(currentUri));
  const startDir = path.dirname(entryPath);
  const projectRoot = await findMsToml(startDir);
  if (!projectRoot) return null;
  let config;
  try {
    config = await loadMsToml(projectRoot);
  } catch {
    return null;
  }
  const resolved = resolveSpecifier(projectRoot, config.srcDir, importTarget.specifier);
  if (!("kind" in resolved) || resolved.kind !== "local") return null;
  const depCached = await getOrLoadCached(resolved.path);
  if (!depCached) return null;
  const depDef = depCached.symbols.getDefinition(importTarget.exportedName);
  if (!depDef) return null;
  const depUri = pathToFileURL(path.resolve(resolved.path)).href;
  const col = depDef.loc.column - 1 + depDef.nameOffset;
  return Location.create(depUri, {
    start: { line: depDef.loc.line - 1, character: col },
    end: { line: depDef.loc.line - 1, character: col + depDef.name.length },
  });
}

async function resolveImportHover(
  currentUri: string,
  importTarget: { specifier: string; exportedName: string }
): Promise<HoverInfo | null> {
  const entryPath = fileURLToPath(new URL(currentUri));
  const startDir = path.dirname(entryPath);
  const projectRoot = await findMsToml(startDir);
  if (!projectRoot) return null;
  let config;
  try {
    config = await loadMsToml(projectRoot);
  } catch {
    return null;
  }
  const resolved = resolveSpecifier(projectRoot, config.srcDir, importTarget.specifier);
  if (!("kind" in resolved) || resolved.kind !== "local") return null;
  const depCached = await getOrLoadCached(resolved.path);
  if (!depCached) return null;
  const depDef = depCached.symbols.getDefinition(importTarget.exportedName);
  if (!depDef) return null;
  const nameCol = depDef.loc.column + depDef.nameOffset;
  return getHoverForSymbol(
    depCached.symbols,
    depCached.program,
    depDef.loc.line,
    nameCol,
    depCached.env
  );
}

/** Collect reference locations from every file in the project that imports (specifier, exportedName). */
async function findProjectReferencesToExport(
  projectRoot: string,
  config: Awaited<ReturnType<typeof loadMsToml>>,
  specifier: string,
  exportedName: string
): Promise<{ definition: Location; references: Location[] } | null> {
  const resolved = resolveSpecifier(projectRoot, config.srcDir, specifier);
  if (!("kind" in resolved) || resolved.kind !== "local") return null;
  const depCached = await getOrLoadCached(resolved.path);
  if (!depCached) return null;
  const depDef = depCached.symbols.getDefinition(exportedName);
  if (!depDef) return null;
  const depUri = pathToFileURL(path.resolve(resolved.path)).href;
  const defCol = depDef.loc.column - 1 + depDef.nameOffset;
  const definition = Location.create(depUri, {
    start: { line: depDef.loc.line - 1, character: defCol },
    end: { line: depDef.loc.line - 1, character: defCol + depDef.name.length },
  });
  const references: Location[] = [];
  const depRefs = findReferences(depCached.symbols, depDef.loc.line, depDef.loc.column + depDef.nameOffset);
  if (depRefs) {
    for (const ref of depRefs.references) {
      references.push(Location.create(depUri, locToRange(ref.loc, depDef.name.length)));
    }
  }
  const msFiles = await listMsFilesInDir(config.srcDir);
  for (const filePath of msFiles) {
    if (path.resolve(filePath) === path.resolve(resolved.path)) continue;
    const fileCached = await getOrLoadCached(filePath);
    if (!fileCached) continue;
    for (const stmt of fileCached.program.body) {
      if (stmt.kind !== "ImportDecl" || stmt.source !== specifier) continue;
      for (const { name, alias } of stmt.names) {
        if (name !== exportedName) continue;
        const bindingName = alias ?? name;
        const refs = fileCached.symbols.getReferences(bindingName);
        const fileUri = pathToFileURL(path.resolve(filePath)).href;
        for (const ref of refs) {
          references.push(Location.create(fileUri, locToRange(ref.loc, bindingName.length)));
        }
      }
    }
  }
  return { definition, references };
}

// ============================================
// Find References
// ============================================

connection.onReferences(async (params): Promise<Location[]> => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return [];

  const uri = params.textDocument.uri;
  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character + 1;

  const result = findReferences(cached.symbols, oneBasedLine, oneBasedCol);
  if (!result) return [];

  const { definition, references } = result;
  const locations: Location[] = [];

  if (definition.importTarget) {
    const proj = await getProjectConfig(uri);
    if (proj) {
      const projectRefs = await findProjectReferencesToExport(
        proj.projectRoot,
        proj.config,
        definition.importTarget.specifier,
        definition.importTarget.exportedName
      );
      if (projectRefs) {
        locations.push(projectRefs.definition);
        locations.push(...projectRefs.references);
        return locations;
      }
    }
    const depLocation = await resolveImportDefinition(uri, definition.importTarget);
    if (depLocation) locations.push(depLocation);
  } else {
    const proj = await getProjectConfig(uri);
    if (proj) {
      const currentPath = fileURLToPath(new URL(uri));
      const specifier = specifierForFile(proj.config.srcDir, currentPath);
      const projectRefs = await findProjectReferencesToExport(
        proj.projectRoot,
        proj.config,
        specifier,
        definition.name
      );
      if (projectRefs) {
        locations.push(projectRefs.definition);
        locations.push(...projectRefs.references);
        return locations;
      }
    }
    const defCol = definition.loc.column - 1 + definition.nameOffset;
    locations.push(Location.create(uri, {
      start: { line: definition.loc.line - 1, character: defCol },
      end: { line: definition.loc.line - 1, character: defCol + definition.name.length },
    }));
  }

  for (const ref of references) {
    locations.push(Location.create(uri, locToRange(ref.loc, definition.name.length)));
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
  import: SymbolKind.Variable,
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
