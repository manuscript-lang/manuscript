// Manuscript Compiler Pipeline
// Combines lexer, parser, type checker, and code generator

import * as path from "path";
import { Parser } from "../parser";
import type { TypeEnvironment } from "../types/environment";
import type { Type } from "../types/types";
import { PassManager, createGlobalEnvironment, getModuleExports, runSingleFileTypecheck, type TypeCheckError } from "../types";
import { CodeGenerator } from "../codegen";
import type * as AST from "../parser/ast";
import { findMsToml, loadMsToml, buildModuleGraph, type ModuleGraph, type MsTomlConfig } from "../modules";
import { resolveStdlibImports } from "../stdlib/loader";

export interface CompileResult {
  success: boolean;
  code?: string;
  ast?: AST.Program;
  errors: CompileError[];
  warnings: CompileWarning[];
}

export interface CompileError {
  message: string;
  hint?: string;
  line?: number;
  column?: number;
  file?: string;
  phase: "lexer" | "parser" | "typecheck" | "codegen";
}

export interface CompileWarning {
  message: string;
  line?: number;
  column?: number;
  file?: string;
}

export interface CompileOptions {
  filename?: string;
  typeCheck?: boolean;
  emitRuntimeImport?: boolean;
}

export interface ParseResult {
  success: boolean;
  ast?: AST.Program;
  errors: CompileError[];
}

export interface TypecheckSingleResult {
  program: AST.Program;
  env: TypeEnvironment;
  errors: CompileError[];
  warnings: CompileWarning[];
}

function toCompileError(te: TypeCheckError, filePath: string): CompileError {
  return {
    message: te.message,
    hint: te.hint,
    line: te.loc?.line,
    column: te.loc?.column,
    file: filePath,
    phase: "typecheck",
  };
}

export function parseSource(source: string, filename?: string): ParseResult {
  const errors: CompileError[] = [];
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
    });
    return { success: false, errors };
  }
}

export interface ProjectCompileOptions {
  typeCheck?: boolean;
  outDir?: string;
  module?: "esm" | "cjs";
  emitRuntimeImport?: boolean;
}

export interface ProjectCompileResult {
  success: boolean;
  outputs: Map<string, string>;
  errors: CompileError[];
  warnings: CompileWarning[];
  config?: MsTomlConfig;
}

/**
 * Core single-file pipeline: parse -> typecheck -> optional codegen.
 * Single source of truth for all single-file operations.
 */
export function compileSingle(
  source: string,
  options: CompileOptions = {},
  skipCodegen = false
): CompileResult & { env?: TypeEnvironment } {
  const errors: CompileError[] = [];
  const warnings: CompileWarning[] = [];
  const filename = options.filename ?? "<anonymous>";
  let env: TypeEnvironment | undefined;

  const parseResult = parseSource(source, filename);
  if (!parseResult.success) return { success: false, errors: parseResult.errors, warnings };
  const ast = parseResult.ast!;

  if (options.typeCheck !== false) {
    try {
      const result = runSingleFileTypecheck(ast);
      env = result.env;
      errors.push(...result.errors.map(te => toCompileError(te, filename)));
      warnings.push(...result.warnings.map(w => ({ message: w, file: filename })));
      if (errors.length > 0) return { success: false, ast, errors, warnings, env };
    } catch (error: unknown) {
      const e = error as Error;
      errors.push({ message: e.message ?? String(error), hint: (error as { hint?: string }).hint, file: filename, phase: "typecheck" });
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
    errors.push({ message: e.message ?? String(error), file: filename, phase: "codegen" });
    return { success: false, ast, errors, warnings, env };
  }
}

/** Typecheck-only API: delegates to compileSingle with skipCodegen. */
export function typecheckSingle(source: string, options: CompileOptions = {}): TypecheckSingleResult | null {
  const result = compileSingle(source, options, true);
  if (!result.ast) return null;
  return { program: result.ast, env: result.env!, errors: result.errors, warnings: result.warnings };
}

/**
 * Compile Manuscript source code to JavaScript
 */
export function compile(source: string, options: CompileOptions = {}): CompileResult {
  return compileSingle(source, options);
}

/**
 * Type check Manuscript source code without generating code
 */
export function check(source: string, options: CompileOptions = {}): CompileResult {
  return compileSingle(source, options, true);
}

/**
 * Parse Manuscript source code and return AST
 */
export function parse(source: string, options: CompileOptions = {}): CompileResult {
  const parseResult = parseSource(source, options.filename ?? "<anonymous>");
  if (!parseResult.success) return { ...parseResult, success: false, warnings: [] };
  return { success: true, ast: parseResult.ast, errors: [], warnings: [] };
}

function relPathFromSrc(srcDir: string, filePath: string): string {
  return path
    .relative(srcDir, path.resolve(filePath))
    .replace(/\.ms$/i, "")
    .replace(/\\/g, "/");
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
  srcDir: string,
  fromFilePath: string,
  toFilePath: string
): string {
  const fromRel = relPathFromSrc(srcDir, fromFilePath);
  const toRel = relPathFromSrc(srcDir, toFilePath);
  const fromDir = path.dirname(`${fromRel  }.js`);
  const toFile = `${toRel  }.js`;
  return path.relative(fromDir, toFile).replace(/\\/g, "/");
}

function runProjectTypecheckLoop(
  graph: ModuleGraph,
  programs: Map<string, AST.Program>,
  entryAbs: string,
  typeCheck: boolean
): {
  moduleExportsMap: Map<string, Map<string, Type>>;
  errors: CompileError[];
  warnings: CompileWarning[];
  entryProgram?: AST.Program;
  entryEnv?: TypeEnvironment;
} {
  const moduleExportsMap = new Map<string, Map<string, Type>>();
  const errors: CompileError[] = [];
  const warnings: CompileWarning[] = [];
  const passManager = PassManager.createDefault();
  let entryProgram: AST.Program | undefined;
  let entryEnv: TypeEnvironment | undefined;

  for (const filePath of graph.order) {
    const program = programs.get(filePath)!;
    const env = createGlobalEnvironment();

    // Resolve local imports
    const thisImports = graph.specifierToPath.get(path.resolve(filePath));
    if (thisImports) {
      for (const [specifier, resolvedPath] of thisImports) {
        const depExports = moduleExportsMap.get(path.resolve(resolvedPath));
        if (!depExports) continue;
        for (const decl of program.body) {
          if (decl.kind !== "ImportDecl" || decl.source !== specifier) continue;
          for (const { name, alias } of decl.names) {
            const type = depExports.get(name);
            if (type === undefined) {
              errors.push({
                message: `Module "${specifier}" does not export "${name}".`,
                file: filePath,
                line: decl.loc?.line,
                column: decl.loc?.column,
                phase: "typecheck",
              });
              continue;
            }
            const bindingName = alias ?? name;
            try {
              env.define(bindingName, type, false);
            } catch {
              errors.push({
                message: `Cannot import "${name}": shadows builtin; use an alias.`,
                file: filePath,
                line: decl.loc?.line,
                phase: "typecheck",
              });
            }
          }
        }
      }
    }

    const stdlibErrors = resolveStdlibImports(program, env);
    for (const te of stdlibErrors) errors.push(toCompileError(te, filePath));

    const result = passManager.runWithEnv(program, env);
    if (typeCheck) {
      for (const te of result.errors) errors.push(toCompileError(te, filePath));
      for (const w of result.warnings) warnings.push({ message: w, file: filePath });
    }

    const exportResult = getModuleExports(program, result.env);
    for (const e of exportResult.errors) {
      errors.push({ message: e.message, file: filePath, line: e.loc?.line, column: e.loc?.column, phase: "typecheck" });
    }
    moduleExportsMap.set(path.resolve(filePath), exportResult.exports);

    if (path.resolve(filePath) === entryAbs) {
      entryProgram = program;
      entryEnv = result.env;
    }
  }

  return { moduleExportsMap, errors, warnings, entryProgram, entryEnv };
}

export interface ProjectInitOptions {
  entrySource?: string;
  entryAST?: AST.Program;
}

export interface ProjectInitResult {
  config: MsTomlConfig;
  graph: ModuleGraph;
  programs: Map<string, AST.Program>;
  errors: CompileError[];
}

export async function initProject(
  entryPath: string,
  readFile: (filePath: string) => Promise<string>,
  options?: ProjectInitOptions
): Promise<ProjectInitResult | null> {
  const entryAbs = path.resolve(entryPath);
  const startDir = path.dirname(entryAbs);
  const projectRoot = await findMsToml(startDir);
  if (!projectRoot) return null;

  let config: MsTomlConfig;
  try {
    config = await loadMsToml(projectRoot);
  } catch {
    return null;
  }

  const effectiveReadFile =
    options?.entrySource != null
      ? (filePath: string) =>
          path.resolve(filePath) === entryAbs ? Promise.resolve(options.entrySource!) : readFile(filePath)
      : readFile;

  const graph = await buildModuleGraph(
    entryAbs,
    config.projectRoot,
    config.srcDir,
    effectiveReadFile
  );

  const errors: CompileError[] = [];
  if (graph.errors.length > 0) {
    for (const e of graph.errors) {
      let line: number | undefined;
      let column: number | undefined;
      if (e.file && e.specifier) {
        if (path.resolve(e.file) === entryAbs && options?.entryAST) {
          const loc = findImportDeclLoc(options.entryAST, e.specifier);
          if (loc) {
            line = loc.line;
            column = loc.column;
          }
        } else {
          const source = await effectiveReadFile(e.file);
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
      errors.push({
        message: e.message,
        file: e.file,
        line,
        column,
        phase: "typecheck",
      });
    }
    return { config, graph, programs: new Map(), errors };
  }

  const programs = new Map<string, AST.Program>();
  for (const filePath of graph.order) {
    if (path.resolve(filePath) === entryAbs && options?.entryAST) {
      programs.set(filePath, options.entryAST);
      continue;
    }
    const source = await effectiveReadFile(filePath);
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
  options: ProjectCompileOptions = {}
): Promise<ProjectCompileResult> {
  const errors: CompileError[] = [];
  const warnings: CompileWarning[] = [];
  const outputs = new Map<string, string>();
  const entryAbs = path.resolve(entryPath);

  const readFile = async (filePath: string): Promise<string> => {
    const fs = await import("fs/promises");
    return fs.readFile(path.resolve(filePath), "utf-8");
  };

  const init = await initProject(entryPath, readFile);
  if (!init) {
    errors.push({
      message: "No ms.toml found (required when using imports).",
      file: entryPath,
      phase: "typecheck",
    });
    return { success: false, outputs, errors, warnings };
  }
  const { config, graph, programs } = init;
  for (const e of init.errors) errors.push(e);
  if (errors.length > 0) return { success: false, outputs, errors, warnings };

  const typeCheck = options.typeCheck !== false;
  const loopResult = runProjectTypecheckLoop(graph, programs, entryAbs, typeCheck);
  const { errors: loopErrors, warnings: loopWarnings } = loopResult;
  for (const e of loopErrors) errors.push(e);
  for (const w of loopWarnings) warnings.push(w);

  if (errors.length > 0) {
    return { success: false, outputs, errors, warnings };
  }

  for (const filePath of graph.order) {
    const program = programs.get(filePath)!;
    const thisSpecifiers = graph.specifierToPath.get(path.resolve(filePath));
    const importEmitPaths = new Map<string, string>();
    if (thisSpecifiers) {
      for (const [specifier, resolvedPath] of thisSpecifiers) {
        const emitPath = emitPathFromTo(config.srcDir, filePath, resolvedPath);
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

  if (options.outDir) {
    const fs = await import("fs/promises");
    await fs.mkdir(options.outDir, { recursive: true });
    for (const [filePath, code] of outputs) {
      const rel = `${path.relative(config.srcDir, filePath).replace(/\.ms$/i, "")  }.js`;
      const outPath = path.join(options.outDir, rel);
      await fs.mkdir(path.dirname(outPath), { recursive: true });
      await fs.writeFile(outPath, code);
    }
  }

  return { success: true, outputs, errors, warnings, config };
}

export interface TypecheckDocumentInProjectResult {
  program: AST.Program;
  env: TypeEnvironment;
  errors: CompileError[];
  warnings: CompileWarning[];
}

/**
 * Typecheck a single document in project context (for LSP). Uses entrySource
 * for the entry file and readFile for dependencies. Returns null if no ms.toml.
 */
export async function typecheckDocumentInProject(
  entryPath: string,
  entrySource: string,
  readFile: (filePath: string) => Promise<string>
): Promise<TypecheckDocumentInProjectResult | null> {
  const entryAbs = path.resolve(entryPath);
  const entryParsed = parseSource(entrySource, entryPath);
  if (!entryParsed.success || !entryParsed.ast) return null;
  const entryAST = entryParsed.ast;

  const init = await initProject(entryPath, readFile, { entrySource, entryAST });
  if (!init) return null;

  const errors: CompileError[] = [...init.errors];
  const warnings: CompileWarning[] = [];
  if (init.errors.length > 0) {
    return { program: entryAST, env: createGlobalEnvironment(), errors, warnings };
  }

  const loopResult = runProjectTypecheckLoop(init.graph, init.programs, entryAbs, true);
  for (const e of loopResult.errors) errors.push(e);
  for (const w of loopResult.warnings) warnings.push(w);
  const { entryProgram, entryEnv } = loopResult;

  if (!entryProgram || !entryEnv) {
    return { program: entryAST, env: createGlobalEnvironment(), errors, warnings };
  }
  return { program: entryProgram, env: entryEnv, errors, warnings };
}

/**
 * Format compile errors for display (LLM-friendly format)
 */
export function formatErrors(errors: CompileError[], source?: string): string {
  const lines = source?.split("\n") || [];
  
  return errors.map(error => {
    let msg = `[${error.phase}] ${error.message}`;
    
    if (error.file) {
      msg = `${error.file}: ${msg}`;
    }
    
    if (error.line !== undefined) {
      msg += `\n  at line ${error.line}`;
      if (error.column !== undefined) {
        msg += `, column ${error.column}`;
      }
      
      // Show source context if available
      if (lines[error.line - 1]) {
        const line = lines[error.line - 1];
        msg += `\n\n  ${error.line} | ${line}`;
        if (error.column !== undefined) {
          const padding = " ".repeat(String(error.line).length + 3 + error.column - 1);
          msg += `\n  ${padding}^`;
        }
      }
    }
    
    // Add hint for fixing the problem
    if (error.hint) {
      msg += `\n\n  Hint: ${error.hint}`;
    }
    
    return msg;
  }).join("\n\n");
}
