// Manuscript Compiler Pipeline
// Combines lexer, parser, type checker, and code generator. No Node fs/path; host is passed from CLI/LSP.

import type { CompileHost } from "../shared/host";
import { Parser } from "../parser";
import type { TypeEnvironment } from "../types/environment";
import type { Type } from "../types/types";
import { createGlobalEnvironment, runSingleFileTypecheck, runProjectTypecheck, type GetInitialEnvResult } from "../types";
import { CodeGenerator } from "../codegen";
import type * as AST from "../parser/ast";
import { findMsToml, loadMsToml, buildModuleGraph, type ModuleGraph, type MsTomlConfig } from "../modules";
import { resolveStdlibImports } from "../stdlib/loader";
import { toDiagnostic, warningToDiagnostic, type Diagnostic } from "../shared/diagnostics";

export type { Diagnostic };

export interface CompileResult {
  success: boolean;
  code?: string;
  ast?: AST.Program;
  errors: Diagnostic[];
  warnings: Diagnostic[];
}

export interface CompileOptions {
  filename?: string;
  typeCheck?: boolean;
  emitRuntimeImport?: boolean;
}

export interface ParseResult {
  success: boolean;
  ast?: AST.Program;
  errors: Diagnostic[];
}

export interface TypecheckSingleResult {
  program: AST.Program;
  env: TypeEnvironment;
  errors: Diagnostic[];
  warnings: Diagnostic[];
}

export function parseSource(source: string, filename?: string): ParseResult {
  const errors: Diagnostic[] = [];
  const file = filename ?? "<anonymous>";
  try {
    const ast = new Parser(source).parse();
    return { success: true, ast, errors };
  } catch (error: unknown) {
    const e = error as Error & { name?: string; message?: string; hint?: string; token?: { loc?: { line?: number; column?: number } }; loc?: { line?: number; column?: number } };
    const phase = e.name === "LexerError" ? "lexer" : "parser";
    errors.push({
      message: e.message ?? String(error),
      hint: e.hint,
      line: e.token?.loc?.line ?? e.loc?.line,
      column: e.token?.loc?.column ?? e.loc?.column,
      file,
      phase,
      severity: "error",
    });
    return { success: false, errors };
  }
}

export interface ProjectCompileOptions {
  host: CompileHost;
  typeCheck?: boolean;
  outDir?: string;
  module?: "esm" | "cjs";
  emitRuntimeImport?: boolean;
  /** In-memory entry content (e.g. unsaved buffer); overrides host.readFile for entry path. */
  entrySource?: string;
  /** When writing outDir; required if outDir is set. */
  writeFile?: (path: string, content: string) => Promise<void>;
  mkdir?: (path: string, opts?: { recursive: boolean }) => Promise<void>;
}

export interface ProjectCompileResult {
  success: boolean;
  outputs: Map<string, string>;
  errors: Diagnostic[];
  warnings: Diagnostic[];
  config?: MsTomlConfig;
}

/**
 * Core single-file pipeline: parse -> typecheck -> optional codegen.
 */
export function compileSingle(
  source: string,
  options: CompileOptions = {},
  skipCodegen = false
): CompileResult & { env?: TypeEnvironment } {
  const errors: Diagnostic[] = [];
  const warnings: Diagnostic[] = [];
  const filename = options.filename ?? "<anonymous>";
  let env: TypeEnvironment | undefined;

  const parseResult = parseSource(source, filename);
  if (!parseResult.success) return { success: false, errors: parseResult.errors, warnings };
  const ast = parseResult.ast!;

  if (options.typeCheck !== false) {
    try {
      const result = runSingleFileTypecheck(ast, resolveStdlibImports);
      env = result.env;
      errors.push(...result.errors.map((te) => toDiagnostic(te, filename)));
      warnings.push(...result.warnings.map((w) => warningToDiagnostic(w, filename)));
      if (errors.length > 0) return { success: false, ast, errors, warnings, env };
    } catch (error: unknown) {
      const e = error as Error;
      errors.push({
        message: e.message ?? String(error),
        hint: (error as { hint?: string }).hint,
        file: filename,
        phase: "typecheck",
        severity: "error",
      });
      return { success: false, ast, errors, warnings };
    }
  }

  if (skipCodegen) {
    return { success: errors.length === 0, ast, errors, warnings, env };
  }

  try {
    const code = new CodeGenerator({ emitRuntimeImport: options.emitRuntimeImport !== false }).generate(ast);
    return { success: true, code, ast, errors, warnings, env };
  } catch (error: unknown) {
    const e = error as Error;
    errors.push({
      message: e.message ?? String(error),
      file: filename,
      phase: "codegen",
      severity: "error",
    });
    return { success: false, ast, errors, warnings, env };
  }
}

export function typecheckSingle(source: string, options: CompileOptions = {}): TypecheckSingleResult | null {
  const result = compileSingle(source, options, true);
  if (!result.ast) return null;
  return { program: result.ast, env: result.env!, errors: result.errors, warnings: result.warnings };
}

export function compile(source: string, options: CompileOptions = {}): CompileResult {
  return compileSingle(source, options);
}

export function check(source: string, options: CompileOptions = {}): CompileResult {
  return compileSingle(source, options, true);
}

export function parse(source: string, options: CompileOptions = {}): CompileResult {
  const parseResult = parseSource(source, options.filename ?? "<anonymous>");
  if (!parseResult.success) return { ...parseResult, success: false, warnings: [] };
  return { success: true, ast: parseResult.ast, errors: [], warnings: [] };
}

function relPathFromSrc(host: CompileHost, srcDir: string, filePath: string): string {
  return host
    .relative(srcDir, host.resolvePath(filePath))
    .replace(/\.ms$/i, "")
    .replace(/\\/g, "/");
}

function makeReadFile(
  host: CompileHost,
  entryPath: string,
  entrySource?: string
): (p: string) => Promise<string> {
  const entryAbs = host.resolvePath(entryPath);
  return entrySource != null
    ? (p) =>
        host.resolvePath(p) === entryAbs ? Promise.resolve(entrySource) : host.readFile(host.resolvePath(p))
    : (p) => host.readFile(host.resolvePath(p));
}

function findImportDeclLoc(program: AST.Program, specifier: string): { line: number; column: number } | undefined {
  for (const stmt of program.body) {
    if (stmt.kind === "ImportDecl" && stmt.source === specifier && stmt.loc) {
      return { line: stmt.loc.line, column: stmt.loc.column };
    }
  }
  return undefined;
}

function emitPathFromTo(
  host: CompileHost,
  srcDir: string,
  fromFilePath: string,
  toFilePath: string
): string {
  const fromRel = relPathFromSrc(host, srcDir, fromFilePath);
  const toRel = relPathFromSrc(host, srcDir, toFilePath);
  const fromDir = host.dirname(fromRel + ".js");
  const toFile = toRel + ".js";
  return host.relative(fromDir, toFile).replace(/\\/g, "/");
}

function buildProjectTypecheckInitialEnv(
  host: CompileHost,
  graph: ModuleGraph,
  programs: Map<string, AST.Program>
): (filePath: string, moduleExportsMap: Map<string, Map<string, Type>>) => GetInitialEnvResult {
  return (filePath: string, moduleExportsMap: Map<string, Map<string, Type>>) => {
    const env = createGlobalEnvironment();
    const errors: Diagnostic[] = [];
    const program = programs.get(filePath)!;
    const thisImports = graph.specifierToPath.get(host.resolvePath(filePath));
    if (thisImports) {
      for (const [specifier, resolvedPath] of thisImports) {
        const depExports = moduleExportsMap.get(host.resolvePath(resolvedPath));
        if (!depExports) continue;
        for (const decl of program.body) {
          if (decl.kind !== "ImportDecl" || decl.source !== specifier) continue;
          for (const { name, alias } of decl.names) {
            const type = depExports.get(name);
            if (type === undefined) {
              errors.push(toDiagnostic({ message: `Module "${specifier}" does not export "${name}".`, loc: decl.loc }, filePath));
              continue;
            }
            const bindingName = alias ?? name;
            try {
              env.define(bindingName, type, false);
            } catch {
              errors.push(toDiagnostic({ message: `Cannot import "${name}": shadows builtin; use an alias.`, loc: decl.loc }, filePath));
            }
          }
        }
      }
    }
    return { env, errors };
  };
}

export interface ProjectInitOptions {
  entrySource?: string;
  entryAST?: AST.Program;
}

export interface ProjectInitResult {
  config: MsTomlConfig;
  graph: ModuleGraph;
  programs: Map<string, AST.Program>;
  errors: Diagnostic[];
}

export async function initProject(
  entryPath: string,
  host: CompileHost,
  readFile: (filePath: string) => Promise<string>,
  options?: ProjectInitOptions
): Promise<ProjectInitResult | null> {
  const entryAbs = host.resolvePath(entryPath);
  const startDir = host.dirname(entryAbs);
  const projectRoot = await findMsToml(host, startDir);
  if (!projectRoot) return null;

  let config: MsTomlConfig;
  try {
    config = await loadMsToml(host, projectRoot);
  } catch {
    return null;
  }

  const graph = await buildModuleGraph(host, entryAbs, config.projectRoot, config.srcDir, readFile);

  const errors: Diagnostic[] = [];
  if (graph.errors.length > 0) {
    for (const e of graph.errors) {
      let line: number | undefined;
      let column: number | undefined;
      if (e.file && e.specifier) {
        if (host.resolvePath(e.file) === entryAbs && options?.entryAST) {
          const loc = findImportDeclLoc(options.entryAST, e.specifier);
          if (loc) {
            line = loc.line;
            column = loc.column;
          }
        } else {
          const source = await readFile(e.file);
          const parsed = parseSource(source, e.file);
          if (parsed.success && parsed.ast) {
            const loc = findImportDeclLoc(parsed.ast, e.specifier);
            if (loc) {
              line = loc.line;
              column = loc.column;
            }
          }
        }
      }
      errors.push(toDiagnostic({ message: e.message, loc: line != null && column != null ? { line, column } : undefined }, e.file ?? ""));
    }
    return { config, graph, programs: new Map(), errors };
  }

  const programs = new Map<string, AST.Program>();
  for (const filePath of graph.order) {
    if (host.resolvePath(filePath) === entryAbs && options?.entryAST) {
      programs.set(filePath, options.entryAST);
      continue;
    }
    const source = await readFile(filePath);
    const parsed = parseSource(source, filePath);
    if (!parsed.success || !parsed.ast) {
      errors.push(...parsed.errors);
      return { config, graph, programs, errors };
    }
    programs.set(filePath, parsed.ast);
  }
  return { config, graph, programs, errors };
}

export async function compileProject(
  entryPath: string,
  options: ProjectCompileOptions
): Promise<ProjectCompileResult> {
  const { host } = options;
  const errors: Diagnostic[] = [];
  const warnings: Diagnostic[] = [];
  const outputs = new Map<string, string>();
  const entryAbs = host.resolvePath(entryPath);
  const init = await initProject(entryPath, host, makeReadFile(host, entryPath, options.entrySource));
  if (!init) {
    errors.push(toDiagnostic({ message: "No ms.toml found (required when using imports)." }, entryPath));
    return { success: false, outputs, errors, warnings };
  }
  const { config, graph, programs } = init;
  for (const e of init.errors) errors.push(e);
  if (errors.length > 0) return { success: false, outputs, errors, warnings };

  const typeCheck = options.typeCheck !== false;
  const getProgram = (filePath: string) => programs.get(filePath)!;
  const getInitialEnv = buildProjectTypecheckInitialEnv(host, graph, programs);
  const loopResult = runProjectTypecheck(graph.order, getProgram, getInitialEnv, {
    typeCheck,
    entryAbs,
    resolvePath: host.resolvePath.bind(host),
    getStdlibErrors: resolveStdlibImports,
  });
  for (const e of loopResult.errors) errors.push(e);
  for (const w of loopResult.warnings) warnings.push(w);

  if (errors.length > 0) {
    return { success: false, outputs, errors, warnings };
  }

  for (const filePath of graph.order) {
    const program = programs.get(filePath)!;
    const thisSpecifiers = graph.specifierToPath.get(host.resolvePath(filePath));
    const importEmitPaths = new Map<string, string>();
    if (thisSpecifiers) {
      for (const [specifier, resolvedPath] of thisSpecifiers) {
        const emitPath = emitPathFromTo(host, config.srcDir, filePath, resolvedPath);
        importEmitPaths.set(specifier, emitPath);
      }
    }
    const generator = new CodeGenerator({
      emitRuntimeImport: options.emitRuntimeImport !== false,
      module: options.module ?? "cjs",
      importEmitPaths,
    });
    const code = generator.generate(program);
    outputs.set(filePath, code);
  }

  if (options.outDir && options.writeFile && options.mkdir) {
    await options.mkdir(options.outDir, { recursive: true });
    for (const [filePath, code] of outputs) {
      const rel = host.relative(config.srcDir, filePath).replace(/\.ms$/i, "") + ".js";
      const outPath = host.joinPaths(options.outDir, rel);
      await options.mkdir(host.dirname(outPath), { recursive: true });
      await options.writeFile(outPath, code);
    }
  }

  return { success: true, outputs, errors, warnings, config };
}

export interface TypecheckDocumentInProjectResult {
  program: AST.Program;
  env: TypeEnvironment;
  errors: Diagnostic[];
  warnings: Diagnostic[];
}

/**
 * Typecheck the entry file in project context (for LSP). Uses the same codepath as checkEntry
 * with in-memory entry content. Returns null when not in a project so LSP can fall back to single-file.
 */
export async function typecheckDocumentInProject(
  entryPath: string,
  entrySource: string,
  host: CompileHost
): Promise<TypecheckDocumentInProjectResult | null> {
  const result = await checkEntry(entryPath, { host, typeCheck: true, entrySource });
  if (!result.inProject) return null;
  const program = result.entryProgram ?? (() => {
    const parsed = parseSource(entrySource, entryPath);
    return parsed.success ? parsed.ast : undefined;
  })();
  const env = result.entryEnv ?? createGlobalEnvironment();
  return {
    program: program!,
    env,
    errors: result.errors,
    warnings: result.warnings,
  };
}

export { formatErrors } from "../shared/diagnostics";

export interface CompileEntryOptions extends CompileOptions, Partial<Omit<ProjectCompileOptions, "host">> {
  host: CompileHost;
  /** When set, use this content for the entry file instead of readFile(entryPath). Used by LSP for unsaved buffers. */
  entrySource?: string;
}

export interface CompileEntryResult {
  success: boolean;
  outputs: Map<string, string>;
  errors: Diagnostic[];
  warnings: Diagnostic[];
  config?: MsTomlConfig;
  /** True when entry was inside a project (ms.toml). Used by LSP to decide project vs single-file. */
  inProject?: boolean;
  /** Set when typecheck ran and entry is in a project. Used by LSP for symbol table. */
  entryProgram?: AST.Program;
  /** Set when typecheck ran and entry is in a project. Used by LSP for symbol table. */
  entryEnv?: TypeEnvironment;
}

export async function compileEntry(entryPath: string, options: CompileEntryOptions): Promise<CompileEntryResult> {
  const host = options.host;
  const entryAbs = host.resolvePath(entryPath);
  const projectRoot = await findMsToml(host, host.dirname(entryAbs));
  if (projectRoot) {
    const result = await compileProject(entryPath, { ...options });
    return {
      success: result.success,
      outputs: result.outputs,
      errors: result.errors,
      warnings: result.warnings,
      config: result.config,
      inProject: true,
    };
  }
  const source =
    options.entrySource ??
    (await host.readFile(host.resolvePath(entryPath)));
  const result = compile(source, { filename: entryPath, ...options });
  const outputs = new Map<string, string>();
  if (result.code) outputs.set(entryPath, result.code);
  return {
    success: result.success,
    outputs,
    errors: result.errors,
    warnings: result.warnings,
    inProject: false,
  };
}

export async function checkEntry(entryPath: string, options: CompileEntryOptions): Promise<CompileEntryResult> {
  const host = options.host;
  const entryAbs = host.resolvePath(entryPath);
  const projectRoot = await findMsToml(host, host.dirname(entryAbs));
  if (projectRoot) {
    const entryAST =
      options.entrySource != null
        ? (() => { const p = parseSource(options.entrySource!, entryPath); return p.success ? p.ast : undefined; })()
        : undefined;
    const init = await initProject(entryPath, host, makeReadFile(host, entryPath, options.entrySource), {
      entrySource: options.entrySource,
      entryAST,
    });
    if (!init) {
      return {
        success: false,
        outputs: new Map(),
        errors: [toDiagnostic({ message: "No ms.toml found." }, entryPath)],
        warnings: [],
        inProject: true,
      };
    }
    const getProgram = (filePath: string) => init.programs.get(filePath)!;
    const getInitialEnv = buildProjectTypecheckInitialEnv(host, init.graph, init.programs);
    const loopResult = runProjectTypecheck(init.graph.order, getProgram, getInitialEnv, {
      typeCheck: true,
      entryAbs,
      resolvePath: host.resolvePath.bind(host),
      getStdlibErrors: resolveStdlibImports,
    });
    return {
      success: loopResult.errors.length === 0,
      outputs: new Map(),
      errors: loopResult.errors,
      warnings: loopResult.warnings,
      config: init.config,
      inProject: true,
      entryProgram: loopResult.entryProgram,
      entryEnv: loopResult.entryEnv,
    };
  }
  const source =
    options.entrySource ?? (await host.readFile(host.resolvePath(entryPath)));
  const result = check(source, { filename: entryPath, ...options });
  return {
    success: result.success,
    outputs: new Map(),
    errors: result.errors,
    warnings: result.warnings,
    inProject: false,
  };
}

export interface MsRuntime {
  getTestCount(): number;
  clearTests(): void;
  runTests(): void | Promise<void>;
  runTestsWithResults(): Promise<{ name: string; passed: boolean; error?: string }[]>;
}

export async function runCompiledCode(
  code: string,
  runtime: MsRuntime,
  options?: { wrapInAsync?: boolean }
): Promise<void> {
  const wrapInAsync = options?.wrapInAsync !== false;
  const wrapped = wrapInAsync
    ? `const __ms_runtime = arguments[0]; return (async () => { ${code} })();`
    : `const __ms_runtime = arguments[0]; ${code}`;
  const fn = new Function(wrapped);
  await fn(runtime);
}

export interface RunSourceResult {
  success: boolean;
  errors: Diagnostic[];
  code?: string;
}

export async function runSource(
  source: string,
  options: CompileOptions,
  runtime: MsRuntime
): Promise<RunSourceResult> {
  const result = compile(source, { ...options, emitRuntimeImport: false });
  if (!result.success) return { success: false, errors: result.errors };
  await runCompiledCode(result.code!, runtime, { wrapInAsync: true });
  return { success: true, errors: [], code: result.code };
}

export async function runTestsInSource(
  source: string,
  options: CompileOptions,
  runtime: MsRuntime
): Promise<{ success: boolean; errors: Diagnostic[]; results: { name: string; passed: boolean; error?: string }[] }> {
  const result = compile(source, { ...options, emitRuntimeImport: false });
  if (!result.success) return { success: false, errors: result.errors, results: [] };
  runtime.clearTests();
  await runCompiledCode(result.code!, runtime, { wrapInAsync: false });
  const results = await runtime.runTestsWithResults();
  return { success: true, errors: [], results };
}
