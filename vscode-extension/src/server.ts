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
import { KEYWORDS } from "../../src/lexer/tokens";
import { STDLIB_FUNCTIONS, isBuiltin } from "../../src/builtin";
import { getBuiltinsAST, BUILTINS_PATH_URI } from "../../src/builtin";

// AST traversal
import { visit } from "../../src/types/ast-visitor";

// Type utilities (for completions)
import {
  formatFnSignature,
  formatTypeSignature,
  formatInterfaceSignature,
  resolveObjectType,
  resolveInterfaceType,
} from "../../src/types/type-utils";

// AST query helpers
import { findConstructorCalleeAt } from "../../src/types/ast-query";

// Stdlib extraction
import {
  collectBuiltinsSymbols,
  collectTypeMembersFromProgram,
  type BuiltinsSymbol,
  type TypeMemberInfo,
} from "../../src/builtin/extractor";

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
  getInterfaceMemberCompletions,
  getTypeAnnotationCompletions,
  getDefaultCompletions,
  resolveStdlibDefinition,
  getStdlibHover,
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
import { typecheckDocumentInProject, typecheckSingle, parseSource } from "../../src/cli/compiler";
import { resolveSpecifier, type MsTomlConfig } from "../../src/modules";
import { BUILTIN_PRIMITIVE_TYPES, isStdlibImport } from "../../src/shared/constants";
import { errorsToDiagnostics, warningsToDiagnostics } from "./diagnostics";
import { getProjectConfig, resolveLocalImport } from "./project";

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
    const tc = typecheckSingle(content, { filename: depPath });
    if (!tc) return null;
    const symbols = buildSymbolTable(tc.program, tc.env);
    const cached: CachedDocument = { program: tc.program, env: tc.env, symbols };
    cache.set(uri, cached);
    return cached;
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

/** Specifier for a file path relative to srcDir (e.g. "src/ms/add" for add.ms). */
function specifierForFile(srcDir: string, filePath: string): string {
  const rel = path.relative(srcDir, path.resolve(filePath));
  return rel.replace(/\.ms$/i, "").replace(/\\/g, "/");
}

const builtinsProgram = getBuiltinsAST();
const builtinsSymbols = collectBuiltinsSymbols(builtinsProgram);
const builtinsTypeMembers = collectTypeMembersFromProgram(builtinsProgram);

// Derived constants
const KEYWORD_LIST = Object.keys(KEYWORDS);

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

  if (doc.uri === BUILTINS_PATH_URI) {
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
      diagnostics.push(
        ...errorsToDiagnostics(errors, entryPath),
        ...warningsToDiagnostics(warnings, entryPath)
      );
      connection.sendDiagnostics({ uri: doc.uri, diagnostics });
      return;
    }
  }

  const entryPath = doc.uri.startsWith("file:") ? fileURLToPath(new URL(doc.uri)) : "";
  const tc = typecheckSingle(doc.getText(), { filename: entryPath });
  if (!tc) {
    const parseResult = parseSource(doc.getText(), entryPath);
    diagnostics.push(...errorsToDiagnostics(parseResult.errors));
    connection.sendDiagnostics({ uri: doc.uri, diagnostics });
    return;
  }
  const symbols = buildSymbolTable(tc.program, tc.env);
  cache.set(doc.uri, { program: tc.program, env: tc.env, symbols });
  diagnostics.push(
    ...errorsToDiagnostics(tc.errors),
    ...warningsToDiagnostics(tc.warnings)
  );
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
    return toCompletionItems(getTypeAnnotationCompletions(builtinsSymbols, cached?.program));
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
      const expr = bestExpr as AST.Expr | null;
      const type =
        expr?.kind === "MemberExpr"
          ? expr.object.resolvedType
          : expr?.resolvedType;
      if (type) {
        const builtinCompletions = getTypeMemberCompletions(builtinsTypeMembers, type.kind);
        if (builtinCompletions.length > 0) return toCompletionItems(builtinCompletions);
        const obj = resolveObjectType(cached.program, type, cached.env);
        if (obj) return toCompletionItems(getObjectMemberCompletions(obj));
        const iface = resolveInterfaceType(cached.program, type, cached.env);
        if (iface) return toCompletionItems(getInterfaceMemberCompletions(iface));
      }
    }
    return [];
  }

  // Default: keywords, builtins, scope (scope-aware when we have a parsed program and cursor position). AST uses 1-based line and column.
  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character + 1;
  const infos = getDefaultCompletions(
    cached?.program,
    KEYWORD_LIST,
    STDLIB_FUNCTIONS,
    builtinsSymbols,
    cached ? oneBasedLine : undefined,
    cached ? oneBasedCol : undefined
  );
  const items = toCompletionItems(infos);

  // Attach data for completion resolve (import info, URIs)
  if (cached) {
    for (const item of items) {
      const stmt = cached.program.body.find(
        s => (s.kind === "FnDecl" && s.name === item.label) ||
             (s.kind === "TypeDecl" && s.name === item.label) ||
             (s.kind === "InterfaceDecl" && s.name === item.label)
      );
      if (stmt) {
        if (stmt.kind === "FnDecl") item.data = { uri: params.textDocument.uri, fn: stmt.name };
        else if (stmt.kind === "TypeDecl") item.data = { uri: params.textDocument.uri, type: stmt.name };
        else if (stmt.kind === "InterfaceDecl") item.data = { uri: params.textDocument.uri, type: stmt.name, interface: true };
      }
    }
    for (const s of cached.program.body) {
      if (s.kind === "ImportDecl") {
        for (const { name, alias } of s.names) {
          const existing = items.find(i => i.label === (alias ?? name));
          if (existing) {
            existing.data = { import: true, specifier: s.source, exportedName: name, uri: params.textDocument.uri };
          }
        }
      }
    }
  }
  // Attach fn data for stdlib function resolve
  for (const item of items) {
    if (STDLIB_FUNCTIONS.has(item.label) && !item.data) {
      item.data = { fn: item.label };
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

  if (data.import && data.specifier != null && data.exportedName != null) {
    if (isStdlibImport(data.specifier)) {
      const hoverInfo = getStdlibHover(data.specifier, data.exportedName);
      if (hoverInfo) {
        item.detail = hoverInfo.signature;
        if (hoverInfo.doc) item.documentation = { kind: MarkupKind.Markdown, value: hoverInfo.doc };
      }
      return item;
    }
    const resolved = await resolveLocalImport(data.uri!, data.specifier);
    if (resolved) {
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
          if (s.kind === "InterfaceDecl" && s.name === data.exportedName) {
            const { signature, methods } = formatInterfaceSignature(s);
            item.detail = `interface ${signature}`;
            const doc = s.doc ?? (methods.length ? `**Methods:**\n${methods.map(m => `- \`${m}\``).join("\n")}` : undefined);
            if (doc) item.documentation = { kind: MarkupKind.Markdown, value: doc };
            return item;
          }
        }
      }
    }
    return item;
  }

  if (data.fn) {
    const sym = builtinsSymbols.get(data.fn);
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
      if (data.type && s.kind === "InterfaceDecl" && s.name === data.type) {
        const { methods } = formatInterfaceSignature(s);
        const doc = s.doc ?? (methods.length ? `**Methods:**\n${methods.map(m => `- \`${m}\``).join("\n")}` : undefined);
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
    for (const [, members] of builtinsTypeMembers) {
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

  const builtinSym = builtinsSymbols.get(word);
  if (builtinSym?.signature) return hover(builtinSym.signature, builtinSym.doc);

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

  const builtinSym = builtinsSymbols.get(word);
  if (builtinSym) {
    return Location.create(BUILTINS_PATH_URI, locToRange(builtinSym.loc));
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

async function resolveLocalImportTarget(
  currentUri: string,
  importTarget: { specifier: string; exportedName: string }
): Promise<{ cached: CachedDocument; def: ReturnType<SymbolTable["getDefinition"]>; depUri: string } | null> {
  const resolved = await resolveLocalImport(currentUri, importTarget.specifier);
  if (!resolved) return null;
  const cached = await getOrLoadCached(resolved.path);
  if (!cached) return null;
  const def = cached.symbols.getDefinition(importTarget.exportedName);
  if (!def) return null;
  return { cached, def, depUri: pathToFileURL(path.resolve(resolved.path)).href };
}

async function resolveImportDefinition(
  currentUri: string,
  importTarget: { specifier: string; exportedName: string }
): Promise<Location | null> {
  if (isStdlibImport(importTarget.specifier)) {
    const loc = resolveStdlibDefinition(importTarget.specifier, importTarget.exportedName);
    if (!loc) return null;
    return Location.create(loc.uri, loc.range);
  }
  const result = await resolveLocalImportTarget(currentUri, importTarget);
  if (!result?.def) return null;
  const { def, depUri } = result;
  const col = def.loc.column - 1 + def.nameOffset;
  return Location.create(depUri, {
    start: { line: def.loc.line - 1, character: col },
    end: { line: def.loc.line - 1, character: col + def.name.length },
  });
}

async function resolveImportHover(
  currentUri: string,
  importTarget: { specifier: string; exportedName: string }
): Promise<HoverInfo | null> {
  if (isStdlibImport(importTarget.specifier)) {
    return getStdlibHover(importTarget.specifier, importTarget.exportedName);
  }
  const result = await resolveLocalImportTarget(currentUri, importTarget);
  if (!result?.def) return null;
  const { def, cached } = result;
  const nameCol = def.loc.column + def.nameOffset;
  return getHoverForSymbol(
    cached.symbols,
    cached.program,
    def.loc.line,
    nameCol,
    cached.env
  );
}

/** Collect reference locations from every file in the project that imports (specifier, exportedName). */
async function findProjectReferencesToExport(
  projectRoot: string,
  config: MsTomlConfig,
  specifier: string,
  exportedName: string
): Promise<{ definition: Location; references: Location[] } | null> {
  if (isStdlibImport(specifier)) {
    const defLoc = resolveStdlibDefinition(specifier, exportedName);
    if (!defLoc) return null;
    const definition = Location.create(defLoc.uri, defLoc.range);
    const references: Location[] = [];
    const msFiles = await listMsFilesInDir(config.srcDir);
    for (const filePath of msFiles) {
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
