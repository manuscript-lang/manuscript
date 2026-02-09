// LanguageService — high-level API for Manuscript language tooling
// Protocol-agnostic: no VSCode/LSP types. Server.ts is the thin adapter.

import * as path from "path";
import { pathToFileURL, fileURLToPath } from "node:url";
import type { CompileHost } from "../shared/host";

import { SymbolTable } from "./symbols";
import { buildSymbolTable } from "./symbol-builder";
import {
  resolveDefinition,
  findReferences,
  getRenameLocations,
} from "./resolver";
import { getHoverForSymbol, type HoverInfo } from "./hover";
import { getDocumentSymbols, type DocumentSymbolInfo } from "./document-symbols";
import {
  getTypeAnnotationCompletions,
  getDefaultCompletions,
  getMemberCompletionsAtPosition,
  resolveCompletionDetail,
  type CompletionInfo,
} from "./completions";
import { getImportBindingOnLine } from "./imports";
import { resolveStdlibDefinition, getStdlibHover } from "./stdlib";

import { KEYWORDS } from "../lexer/tokens";
import {
  STDLIB_FUNCTIONS,
  isBuiltin,
  getBuiltinsAST,
  BUILTINS_PATH_URI,
} from "../builtin";
import {
  collectBuiltinsSymbols,
  collectTypeMembersFromProgram,
  type BuiltinsSymbol,
  type TypeMemberInfo,
} from "./builtin-symbols";
import { findConstructorCalleeAt } from "./ast-utils";
import {
  typecheckDocumentInProject,
  typecheckSingle,
  parseSource,
  type Diagnostic,
} from "../compile";
import { resolveSpecifier, type MsTomlConfig } from "../modules";
import { BUILTIN_PRIMITIVE_TYPES, isStdlibImport } from "../shared/constants";
import type { Program } from "../parser/ast";
import type { TypeEnvironment } from "../types/environment";

// ============================================
// Protocol-agnostic result types
// ============================================

export interface DiagnosticInfo {
  line: number;
  col: number;
  endCol: number;
  message: string;
  severity: "error" | "warning";
  file?: string;
}

export interface DefinitionResult {
  uri: string;
  line: number;
  col: number;
  length: number;
}

export interface ReferenceLocation {
  uri: string;
  line: number;
  col: number;
  length: number;
}

export interface RenameLocationInfo {
  line: number;
  col: number;
  length: number;
}

export interface CompletionItemData {
  uri?: string;
  fn?: string;
  type?: string;
  interface?: boolean;
  import?: boolean;
  specifier?: string;
  exportedName?: string;
}

// ============================================
// Host interface (I/O boundary) — extends CompileHost so one object does both.
// ============================================

export interface LanguageServiceHost extends CompileHost {
  listMsFiles(dir: string): Promise<string[]>;
  getProjectConfig(filePath: string): Promise<{ projectRoot: string; config: MsTomlConfig } | null>;
}

// ============================================
// LanguageService
// ============================================

interface CachedDocument {
  program: Program;
  env: TypeEnvironment;
  symbols: SymbolTable;
}

export class LanguageService {
  private host: LanguageServiceHost;
  private cache = new Map<string, CachedDocument>();
  private builtinsProgram: Program;
  private builtinsSymbols: Map<string, BuiltinsSymbol>;
  private builtinsTypeMembers: Map<string, TypeMemberInfo[]>;
  private keywordList: string[];

  constructor(host: LanguageServiceHost) {
    this.host = host;
    this.builtinsProgram = getBuiltinsAST();
    this.builtinsSymbols = collectBuiltinsSymbols(this.builtinsProgram);
    this.builtinsTypeMembers = collectTypeMembersFromProgram(this.builtinsProgram);
    this.keywordList = Object.keys(KEYWORDS);
  }

  private cacheDocument(uri: string, program: Program, env: TypeEnvironment): CachedDocument {
    const symbols = buildSymbolTable(program, env);
    const cached: CachedDocument = { program, env, symbols };
    this.cache.set(uri, cached);
    return cached;
  }

  async validateDocument(filePathOrUri: string, source: string): Promise<DiagnosticInfo[]> {
    const filePath = filePathOrUri.startsWith("file:") ? fileURLToPath(new URL(filePathOrUri)) : filePathOrUri;
    const uri = pathToFileURL(path.resolve(filePath)).href;
    if (uri === BUILTINS_PATH_URI) return [];

    const projectResult = await typecheckDocumentInProject(filePath, source, this.host);
    if (projectResult) {
      this.cacheDocument(uri, projectResult.program, projectResult.env);
      return [
        ...this.errorsToDiagnostics(projectResult.errors, filePath),
        ...this.warningsToDiagnostics(projectResult.warnings, filePath),
      ];
    }
    const tc = typecheckSingle(source, { filename: filePath });
    if (!tc) return this.errorsToDiagnostics(parseSource(source, filePath).errors);
    this.cacheDocument(uri, tc.program, tc.env);
    return [
      ...this.errorsToDiagnostics(tc.errors),
      ...this.warningsToDiagnostics(tc.warnings),
    ];
  }


  getCachedDocument(uri: string): CachedDocument | undefined {
    return this.cache.get(uri);
  }

  // ============================================
  // Completions
  // ============================================

  getCompletions(uri: string, line: number, col: number, lineText: string): (CompletionInfo & { data?: CompletionItemData })[] {
    const cached = this.cache.get(uri);

    // After colon: type completions
    if (lineText.match(/:\s*$/)) {
      return getTypeAnnotationCompletions(this.builtinsSymbols, cached?.program);
    }

    // After dot: member completions
    if (lineText.match(/\.\s*$/)) {
      if (cached) {
        return getMemberCompletionsAtPosition(
          cached.program, cached.env, line, col, this.builtinsTypeMembers
        );
      }
      return [];
    }

    // Default: keywords, builtins, scope
    const infos = getDefaultCompletions(
      cached?.program,
      this.keywordList,
      STDLIB_FUNCTIONS,
      this.builtinsSymbols,
      cached ? line : undefined,
      cached ? col + 1 : undefined
    );

    const items: (CompletionInfo & { data?: CompletionItemData })[] = infos.map(i => ({ ...i }));

    // Attach data for completion resolve
    if (cached) {
      for (const item of items) {
        const stmt = cached.program.body.find(
          s => (s.kind === "FnDecl" && s.name === item.label) ||
               (s.kind === "TypeDecl" && s.name === item.label) ||
               (s.kind === "InterfaceDecl" && s.name === item.label)
        );
        if (stmt) {
          if (stmt.kind === "FnDecl") item.data = { uri, fn: stmt.name };
          else if (stmt.kind === "TypeDecl") item.data = { uri, type: stmt.name };
          else if (stmt.kind === "InterfaceDecl") item.data = { uri, type: stmt.name, interface: true };
        }
      }
      for (const s of cached.program.body) {
        if (s.kind === "ImportDecl") {
          for (const { name, alias } of s.names) {
            const existing = items.find(i => i.label === (alias ?? name));
            if (existing) {
              existing.data = { import: true, specifier: s.source, exportedName: name, uri };
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
  }

  async resolveCompletion(item: CompletionInfo & { data?: CompletionItemData }): Promise<{ detail?: string; doc?: string }> {
    const data = item.data;
    if (!data) return {};

    if (data.import && data.specifier != null && data.exportedName != null) {
      if (isStdlibImport(data.specifier)) {
        const hoverInfo = getStdlibHover(data.specifier, data.exportedName);
        if (hoverInfo) return { detail: hoverInfo.signature, doc: hoverInfo.doc };
        return {};
      }
      const resolved = await this.resolveLocalImport(data.uri!, data.specifier);
      if (resolved) {
        const depCached = await this.getOrLoadCached(resolved.path);
        if (depCached) {
          for (const kind of ["fn", "type", "interface"] as const) {
            const result = resolveCompletionDetail(depCached.program, data.exportedName!, kind);
            if (result) return { detail: result.detail, doc: result.doc };
          }
        }
      }
      return {};
    }

    if (data.fn) {
      const sym = this.builtinsSymbols.get(data.fn);
      if (sym?.doc) return { doc: sym.doc };
    }

    if (data.uri) {
      const cached = this.cache.get(data.uri);
      if (cached) {
        if (data.fn) {
          const result = resolveCompletionDetail(cached.program, data.fn, "fn");
          if (result) return { detail: result.detail, doc: result.doc };
        } else if (data.type) {
          const kind = data.interface ? "interface" as const : "type" as const;
          const result = resolveCompletionDetail(cached.program, data.type, kind);
          if (result) return { doc: result.doc };
        }
      }
    }

    return {};
  }

  // ============================================
  // Hover
  // ============================================

  async getHover(uri: string, line: number, col: number, word: string, isProperty: boolean): Promise<HoverInfo | null> {
    const cached = this.cache.get(uri);
    if (!cached) return null;

    let symbolHover = getHoverForSymbol(cached.symbols, cached.program, line, col, cached.env);
    if (!symbolHover) {
      const def = resolveDefinition(cached.symbols, line, col);
      const importTarget = def?.importTarget ?? getImportBindingOnLine(cached.program, line, word);
      if (importTarget) {
        symbolHover = await this.resolveImportHover(uri, importTarget);
      }
    }
    if (symbolHover) return { signature: symbolHover.signature, doc: symbolHover.doc };

    if (isProperty) {
      for (const [, members] of this.builtinsTypeMembers) {
        const member = members.find(m => m.name === word);
        if (member) {
          if (member.kind === "field") {
            return { signature: `(field) ${word}: ${member.signature}`, doc: member.doc };
          } else {
            const sig = member.signature.startsWith("fn") ? member.signature.slice(2) : member.signature;
            return { signature: `(method) fn ${word}${sig}`, doc: member.doc };
          }
        }
      }
      return null;
    }

    const builtinSym = this.builtinsSymbols.get(word);
    if (builtinSym?.signature) return { signature: builtinSym.signature, doc: builtinSym.doc };

    if (this.keywordList.includes(word)) return { signature: `(keyword) ${word}` };
    if (BUILTIN_PRIMITIVE_TYPES.includes(word)) return { signature: `(type) ${word}` };

    return null;
  }

  // ============================================
  // Document Symbols
  // ============================================

  getDocumentSymbols(uri: string): DocumentSymbolInfo[] {
    const cached = this.cache.get(uri);
    if (!cached) return [];
    return getDocumentSymbols(cached.symbols);
  }

  // ============================================
  // Go to Definition
  // ============================================

  async getDefinition(uri: string, line: number, col: number, word: string): Promise<DefinitionResult | null> {
    const cached = this.cache.get(uri);
    if (!cached) return null;

    let def = resolveDefinition(cached.symbols, line, col);
    if (def) {
      if (def.importTarget) {
        const depLocation = await this.resolveImportDefinition(uri, def.importTarget);
        if (depLocation) return depLocation;
      }
      if (def.id.kind === "type") {
        const ctorCallee = findConstructorCalleeAt(cached.program, line, col);
        if (ctorCallee === def.name) {
          const initDef = cached.symbols.getDefinition(`${def.name}.init`);
          if (initDef) def = initDef;
        }
      }
      const defCol = def.loc.column + def.nameOffset;
      return {
        uri,
        line: def.loc.line,
        col: defCol,
        length: def.name.length,
      };
    }

    const importTarget = getImportBindingOnLine(cached.program, line, word);
    if (importTarget) {
      const depLocation = await this.resolveImportDefinition(uri, importTarget);
      if (depLocation) return depLocation;
    }

    const builtinSym = this.builtinsSymbols.get(word);
    if (builtinSym) {
      return {
        uri: BUILTINS_PATH_URI,
        line: builtinSym.loc.line,
        col: builtinSym.loc.column,
        length: 1,
      };
    }

    return null;
  }

  // ============================================
  // Find References
  // ============================================

  async getReferences(uri: string, line: number, col: number): Promise<ReferenceLocation[]> {
    const cached = this.cache.get(uri);
    if (!cached) return [];

    const result = findReferences(cached.symbols, line, col);
    if (!result) return [];

    const { definition, references } = result;
    const locations: ReferenceLocation[] = [];

    if (definition.importTarget) {
      const proj = await this.host.getProjectConfig(
        uri.startsWith("file:") ? fileURLToPath(new URL(uri)) : uri
      );
      if (proj) {
        const projectRefs = await this.findProjectReferencesToExport(
          proj.projectRoot, proj.config,
          definition.importTarget.specifier, definition.importTarget.exportedName
        );
        if (projectRefs) {
          locations.push(projectRefs.definition);
          locations.push(...projectRefs.references);
          return locations;
        }
      }
      const depLocation = await this.resolveImportDefinition(uri, definition.importTarget);
      if (depLocation) {
        locations.push(depLocation);
      }
    } else {
      const filePath = uri.startsWith("file:") ? fileURLToPath(new URL(uri)) : uri;
      const proj = await this.host.getProjectConfig(filePath);
      if (proj) {
        const specifier = this.specifierForFile(proj.config.srcDir, filePath);
        const projectRefs = await this.findProjectReferencesToExport(
          proj.projectRoot, proj.config, specifier, definition.name
        );
        if (projectRefs) {
          locations.push(projectRefs.definition);
          locations.push(...projectRefs.references);
          return locations;
        }
      }
      const defCol = definition.loc.column + definition.nameOffset;
      locations.push({
        uri,
        line: definition.loc.line,
        col: defCol,
        length: definition.name.length,
      });
    }

    for (const ref of references) {
      locations.push({
        uri,
        line: ref.loc.line,
        col: ref.loc.column,
        length: definition.name.length,
      });
    }
    return locations;
  }

  // ============================================
  // Rename
  // ============================================

  canRename(word: string): boolean {
    return !isBuiltin(word) && !this.keywordList.includes(word) && !BUILTIN_PRIMITIVE_TYPES.includes(word);
  }

  hasDefinitionAt(uri: string, line: number, col: number): boolean {
    const cached = this.cache.get(uri);
    if (!cached) return false;
    return !!resolveDefinition(cached.symbols, line, col);
  }

  getRenameLocations(uri: string, line: number, col: number): RenameLocationInfo[] | null {
    const cached = this.cache.get(uri);
    if (!cached) return null;

    const locations = getRenameLocations(cached.symbols, line, col);
    if (!locations || locations.length === 0) return null;

    return locations.map(loc => ({
      line: loc.loc.line,
      col: loc.loc.column,
      length: loc.length,
    }));
  }

  // ============================================
  // Private helpers
  // ============================================

  private async getOrLoadCached(depPath: string): Promise<CachedDocument | null> {
    const uri = pathToFileURL(path.resolve(depPath)).href;
    const existing = this.cache.get(uri);
    if (existing) return existing;
    let content: string;
    try {
      content = await this.host.readFile(this.host.resolvePath(depPath));
    } catch {
      return null;
    }
    const result = await typecheckDocumentInProject(depPath, content, this.host);
    if (result) return this.cacheDocument(uri, result.program, result.env);
    const tc = typecheckSingle(content, { filename: depPath });
    if (!tc) return null;
    return this.cacheDocument(uri, tc.program, tc.env);
  }

  private async resolveLocalImport(
    currentUri: string,
    specifier: string
  ): Promise<{ path: string } | null> {
    const filePath = currentUri.startsWith("file:") ? fileURLToPath(new URL(currentUri)) : currentUri;
    const proj = await this.host.getProjectConfig(filePath);
    if (!proj) return null;
    const resolved = resolveSpecifier(this.host, proj.projectRoot, proj.config.srcDir, specifier);
    if (!("kind" in resolved) || resolved.kind !== "local") return null;
    return { path: resolved.path };
  }

  private async resolveLocalImportTarget(
    currentUri: string,
    importTarget: { specifier: string; exportedName: string }
  ): Promise<{ cached: CachedDocument; def: ReturnType<SymbolTable["getDefinition"]>; depUri: string } | null> {
    const resolved = await this.resolveLocalImport(currentUri, importTarget.specifier);
    if (!resolved) return null;
    const cached = await this.getOrLoadCached(resolved.path);
    if (!cached) return null;
    const def = cached.symbols.getDefinition(importTarget.exportedName);
    if (!def) return null;
    return { cached, def, depUri: pathToFileURL(path.resolve(resolved.path)).href };
  }

  private async resolveImportDefinition(
    currentUri: string,
    importTarget: { specifier: string; exportedName: string }
  ): Promise<DefinitionResult | null> {
    if (isStdlibImport(importTarget.specifier)) {
      const loc = resolveStdlibDefinition(importTarget.specifier, importTarget.exportedName);
      if (!loc) return null;
      return {
        uri: loc.uri,
        line: loc.range.start.line + 1,
        col: loc.range.start.character + 1,
        length: loc.range.end.character - loc.range.start.character,
      };
    }
    const result = await this.resolveLocalImportTarget(currentUri, importTarget);
    if (!result?.def) return null;
    const { def, depUri } = result;
    const col = def.loc.column + def.nameOffset;
    return {
      uri: depUri,
      line: def.loc.line,
      col,
      length: def.name.length,
    };
  }

  private async resolveImportHover(
    currentUri: string,
    importTarget: { specifier: string; exportedName: string }
  ): Promise<HoverInfo | null> {
    if (isStdlibImport(importTarget.specifier)) {
      return getStdlibHover(importTarget.specifier, importTarget.exportedName);
    }
    const result = await this.resolveLocalImportTarget(currentUri, importTarget);
    if (!result?.def) return null;
    const { def, cached } = result;
    const nameCol = def.loc.column + def.nameOffset;
    return getHoverForSymbol(
      cached.symbols, cached.program, def.loc.line, nameCol, cached.env
    );
  }

  private specifierForFile(srcDir: string, filePath: string): string {
    const rel = path.relative(srcDir, path.resolve(filePath));
    return rel.replace(/\.ms$/i, "").replace(/\\/g, "/");
  }

  private async findProjectReferencesToExport(
    projectRoot: string,
    config: MsTomlConfig,
    specifier: string,
    exportedName: string
  ): Promise<{ definition: ReferenceLocation; references: ReferenceLocation[] } | null> {
    if (isStdlibImport(specifier)) {
      const defLoc = resolveStdlibDefinition(specifier, exportedName);
      if (!defLoc) return null;
      const definition: ReferenceLocation = {
        uri: defLoc.uri,
        line: defLoc.range.start.line + 1,
        col: defLoc.range.start.character + 1,
        length: defLoc.range.end.character - defLoc.range.start.character,
      };
      const references: ReferenceLocation[] = [];
      const msFiles = await this.host.listMsFiles(config.srcDir);
      for (const filePath of msFiles) {
        const fileCached = await this.getOrLoadCached(filePath);
        if (!fileCached) continue;
        for (const stmt of fileCached.program.body) {
          if (stmt.kind !== "ImportDecl" || stmt.source !== specifier) continue;
          for (const { name, alias } of stmt.names) {
            if (name !== exportedName) continue;
            const bindingName = alias ?? name;
            const refs = fileCached.symbols.getReferences(bindingName);
            const fileUri = pathToFileURL(path.resolve(filePath)).href;
            for (const ref of refs) {
              references.push({
                uri: fileUri,
                line: ref.loc.line,
                col: ref.loc.column,
                length: bindingName.length,
              });
            }
          }
        }
      }
      return { definition, references };
    }

    const resolved = resolveSpecifier(this.host, projectRoot, config.srcDir, specifier);
    if (!("kind" in resolved) || resolved.kind !== "local") return null;
    const depCached = await this.getOrLoadCached(resolved.path);
    if (!depCached) return null;
    const depDef = depCached.symbols.getDefinition(exportedName);
    if (!depDef) return null;
    const depUri = pathToFileURL(path.resolve(resolved.path)).href;
    const defCol = depDef.loc.column + depDef.nameOffset;
    const definition: ReferenceLocation = {
      uri: depUri,
      line: depDef.loc.line,
      col: defCol,
      length: depDef.name.length,
    };
    const references: ReferenceLocation[] = [];
    const depRefs = findReferences(depCached.symbols, depDef.loc.line, depDef.loc.column + depDef.nameOffset);
    if (depRefs) {
      for (const ref of depRefs.references) {
        references.push({
          uri: depUri,
          line: ref.loc.line,
          col: ref.loc.column,
          length: depDef.name.length,
        });
      }
    }
    const msFiles = await this.host.listMsFiles(config.srcDir);
    for (const filePath of msFiles) {
      if (path.resolve(filePath) === path.resolve(resolved.path)) continue;
      const fileCached = await this.getOrLoadCached(filePath);
      if (!fileCached) continue;
      for (const stmt of fileCached.program.body) {
        if (stmt.kind !== "ImportDecl" || stmt.source !== specifier) continue;
        for (const { name, alias } of stmt.names) {
          if (name !== exportedName) continue;
          const bindingName = alias ?? name;
          const refs = fileCached.symbols.getReferences(bindingName);
          const fileUri = pathToFileURL(path.resolve(filePath)).href;
          for (const ref of refs) {
            references.push({
              uri: fileUri,
              line: ref.loc.line,
              col: ref.loc.column,
              length: bindingName.length,
            });
          }
        }
      }
    }
    return { definition, references };
  }

  // ============================================
  // Diagnostic conversion helpers
  // ============================================

  private static readonly ERROR_SUFFIX = / at line \d+, column \d+$/;

  private errorsToDiagnostics(diagnostics: Diagnostic[], entryPath?: string): DiagnosticInfo[] {
    const entryAbs = entryPath ? path.resolve(entryPath) : undefined;
    return diagnostics
      .filter((d) => !entryAbs || (d.file && path.resolve(d.file) === entryAbs))
      .map((d) => ({
        line: d.line ?? 1,
        col: d.column ?? 1,
        endCol: (d.column ?? 1) + 10,
        message: d.message.replace(LanguageService.ERROR_SUFFIX, ""),
        severity: "error" as const,
        file: d.file,
      }));
  }

  private warningsToDiagnostics(diagnostics: Diagnostic[], entryPath?: string): DiagnosticInfo[] {
    const entryAbs = entryPath ? path.resolve(entryPath) : undefined;
    return diagnostics
      .filter((d) => !entryAbs || (d.file && path.resolve(d.file) === entryAbs))
      .map((d) => ({
        line: d.line ?? 1,
        col: d.column ?? 1,
        endCol: (d.column ?? 1) + 10,
        message: d.message,
        severity: "warning" as const,
        file: d.file,
      }));
  }
}
