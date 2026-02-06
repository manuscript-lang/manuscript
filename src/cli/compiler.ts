// Manuscript Compiler Pipeline
// Combines lexer, parser, type checker, and code generator

import * as path from "path";
import { Parser } from "../parser";
import type { TypeEnvironment } from "../types/environment";
import type { Type } from "../types/types";
import { PassManager, createGlobalEnvironment, getModuleExports } from "../types";
import { CodeGenerator } from "../codegen";
import type * as AST from "../parser/ast";
import { findMsToml, loadMsToml, buildModuleGraph, type ModuleGraph, type MsTomlConfig, resolveSpecifier } from "../modules";
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
  emitRuntimeImport?: boolean; // Emit import { __ms_runtime } (default: true, set to false for eval)
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
 * Compile Manuscript source code to JavaScript
 */
export function compile(source: string, options: CompileOptions = {}): CompileResult {
  const errors: CompileError[] = [];
  const warnings: CompileWarning[] = [];
  const filename = options.filename || "<anonymous>";

  // Phase 1 & 2: Parse (lexing is done internally by Parser)
  let ast: AST.Program;
  try {
    const parser = new Parser(source);
    ast = parser.parse();
  } catch (error: any) {
    // Determine phase from error type
    const phase = error.name === "LexerError" ? "lexer" : "parser";
    errors.push({
      message: error.message,
      hint: error.hint,
      line: error.token?.loc?.line ?? error.loc?.line,
      column: error.token?.loc?.column ?? error.loc?.column,
      file: filename,
      phase,
    });
    return { success: false, errors, warnings };
  }

  // Phase 3: Type Checking (optional, enabled by default)
  if (options.typeCheck !== false) {
    try {
      const singleGraph: ModuleGraph = {
        order: [filename],
        specifierToPath: new Map(),
        errors: [],
      };
      const programs = new Map<string, AST.Program>([[filename, ast]]);
      const tcResult = runProjectTypecheckLoop(singleGraph, programs, filename, true);
      errors.push(...tcResult.errors);
      warnings.push(...tcResult.warnings);
      
      if (errors.length > 0) {
        return { success: false, ast, errors, warnings };
      }
    } catch (error: any) {
      errors.push({
        message: error.message,
        file: filename,
        phase: "typecheck",
      });
      return { success: false, ast, errors, warnings };
    }
  }

  // Phase 4: Code Generation
  let code: string;
  try {
    const generator = new CodeGenerator({
      emitRuntimeImport: options.emitRuntimeImport !== false,
    });
    code = generator.generate(ast);
  } catch (error: any) {
    errors.push({
      message: error.message,
      file: filename,
      phase: "codegen",
    });
    return { success: false, ast, errors, warnings };
  }

  return { success: true, code, ast, errors, warnings };
}

/**
 * Type check Manuscript source code without generating code
 */
export function check(source: string, options: CompileOptions = {}): CompileResult {
  const errors: CompileError[] = [];
  const warnings: CompileWarning[] = [];
  const filename = options.filename || "<anonymous>";

  // Phase 1 & 2: Parse (lexing is done internally by Parser)
  let ast: AST.Program;
  try {
    const parser = new Parser(source);
    ast = parser.parse();
  } catch (error: any) {
    const phase = error.name === "LexerError" ? "lexer" : "parser";
    errors.push({
      message: error.message,
      hint: error.hint,
      line: error.token?.loc?.line ?? error.loc?.line,
      column: error.token?.loc?.column ?? error.loc?.column,
      file: filename,
      phase,
    });
    return { success: false, errors, warnings };
  }

  // Phase 3: Type Checking
  try {
    const singleGraph: ModuleGraph = {
      order: [filename],
      specifierToPath: new Map(),
      errors: [],
    };
    const programs = new Map<string, AST.Program>([[filename, ast]]);
    const tcResult = runProjectTypecheckLoop(singleGraph, programs, filename, true);
    errors.push(...tcResult.errors);
    warnings.push(...tcResult.warnings);
  } catch (error: any) {
    errors.push({
      message: error.message,
      hint: error.hint,
      file: filename,
      phase: "typecheck",
    });
  }

  return { 
    success: errors.length === 0, 
    ast, 
    errors, 
    warnings 
  };
}

/**
 * Parse Manuscript source code and return AST
 */
export function parse(source: string, options: CompileOptions = {}): CompileResult {
  const errors: CompileError[] = [];
  const warnings: CompileWarning[] = [];
  const filename = options.filename || "<anonymous>";

  // Phase 1 & 2: Parse (lexing is done internally by Parser)
  let ast: AST.Program;
  try {
    const parser = new Parser(source);
    ast = parser.parse();
  } catch (error: any) {
    const phase = error.name === "LexerError" ? "lexer" : "parser";
    errors.push({
      message: error.message,
      hint: error.hint,
      line: error.token?.loc?.line ?? error.loc?.line,
      column: error.token?.loc?.column ?? error.loc?.column,
      file: filename,
      phase,
    });
    return { success: false, errors, warnings };
  }

  return { success: true, ast, errors, warnings };
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
  const fromDir = path.dirname(fromRel + ".js");
  const toFile = toRel + ".js";
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

    // Resolve stdlib imports
    const stdlibErrors = resolveStdlibImports(program, env);
    for (const te of stdlibErrors) {
      errors.push({
        message: te.message,
        line: te.loc?.line,
        column: te.loc?.column,
        file: filePath,
        phase: "typecheck",
      });
    }

    const result = passManager.runWithEnv(program, env);
    if (typeCheck) {
      for (const te of result.errors) {
        errors.push({
          message: te.message,
          hint: te.hint,
          line: te.loc?.line,
          column: te.loc?.column,
          file: filePath,
          phase: "typecheck",
        });
      }
      for (const w of result.warnings) {
        warnings.push({ message: w, file: filePath });
      }
    }

    const exportResult = getModuleExports(program, result.env);
    for (const e of exportResult.errors) {
      errors.push({
        message: e.message,
        file: filePath,
        line: e.loc?.line,
        column: e.loc?.column,
        phase: "typecheck",
      });
    }
    moduleExportsMap.set(path.resolve(filePath), exportResult.exports);

    if (path.resolve(filePath) === entryAbs) {
      entryProgram = program;
      entryEnv = result.env;
    }
  }

  return { moduleExportsMap, errors, warnings, entryProgram, entryEnv };
}

export async function compileProject(
  entryPath: string,
  options: ProjectCompileOptions = {}
): Promise<ProjectCompileResult> {
  const errors: CompileError[] = [];
  const warnings: CompileWarning[] = [];
  const outputs = new Map<string, string>();

  const entryAbs = path.resolve(entryPath);
  const startDir = path.dirname(entryAbs);
  const projectRoot = await findMsToml(startDir);
  if (!projectRoot) {
    errors.push({
      message: "No ms.toml found (required when using imports).",
      file: entryPath,
      phase: "typecheck",
    });
    return { success: false, outputs, errors, warnings };
  }

  let config: MsTomlConfig;
  try {
    config = await loadMsToml(projectRoot);
  } catch (e: unknown) {
    errors.push({
      message: (e as Error).message,
      phase: "typecheck",
    });
    return { success: false, outputs, errors, warnings };
  }

  const readFile = async (filePath: string): Promise<string> => {
    const fs = await import("fs/promises");
    return fs.readFile(path.resolve(filePath), "utf-8");
  };

  const graph = await buildModuleGraph(
    entryAbs,
    config.projectRoot,
    config.srcDir,
    readFile
  );

  if (graph.errors.length > 0) {
    for (const e of graph.errors) {
      let line: number | undefined;
      let column: number | undefined;
      if (e.file && e.specifier) {
        try {
          const src = await readFile(e.file);
          const prog = new Parser(src).parse();
          const loc = findImportDeclLoc(prog, e.specifier);
          if (loc) {
            line = loc.line;
            column = loc.column;
          }
        } catch {
          /* ignore */
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
    return { success: false, outputs, errors, warnings };
  }

  const programs = new Map<string, AST.Program>();
  for (const filePath of graph.order) {
    const source = await readFile(filePath);
    try {
      const program = new Parser(source).parse();
      programs.set(filePath, program);
    } catch (e: unknown) {
      const err = e as Error & { token?: { loc?: { line?: number; column?: number } }; loc?: { line?: number; column?: number } };
      errors.push({
        message: err.message,
        file: filePath,
        line: err.token?.loc?.line ?? err.loc?.line,
        column: err.token?.loc?.column ?? err.loc?.column,
        phase: "parser",
      });
      return { success: false, outputs, errors, warnings };
    }
  }

  const typeCheck = options.typeCheck !== false;
  const loopResult = runProjectTypecheckLoop(graph, programs, entryAbs, typeCheck);
  const { moduleExportsMap, errors: loopErrors, warnings: loopWarnings } = loopResult;
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
      const rel = path.relative(config.srcDir, filePath).replace(/\.ms$/i, "") + ".js";
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
  const startDir = path.dirname(entryAbs);
  const projectRoot = await findMsToml(startDir);
  if (!projectRoot) return null;

  let config;
  try {
    config = await loadMsToml(projectRoot);
  } catch {
    return null;
  }

  const readFileWithEntry = async (filePath: string): Promise<string> =>
    path.resolve(filePath) === entryAbs ? entrySource : readFile(filePath);

  const graph = await buildModuleGraph(
    entryAbs,
    config.projectRoot,
    config.srcDir,
    readFileWithEntry
  );

  const errors: CompileError[] = [];
  const warnings: CompileWarning[] = [];

  if (graph.errors.length > 0) {
    let entryProgram: AST.Program | undefined;
    try {
      entryProgram = new Parser(entrySource).parse();
    } catch {
      return null;
    }
    for (const e of graph.errors) {
      const loc = e.specifier && e.file && path.resolve(e.file) === entryAbs
        ? findImportDeclLoc(entryProgram!, e.specifier)
        : undefined;
      errors.push({
        message: e.message,
        file: e.file,
        line: loc?.line,
        column: loc?.column,
        phase: "typecheck",
      });
    }
    return { program: entryProgram!, env: createGlobalEnvironment(), errors, warnings };
  }

  const programs = new Map<string, AST.Program>();
  for (const filePath of graph.order) {
    const source = await readFileWithEntry(filePath);
    try {
      programs.set(filePath, new Parser(source).parse());
    } catch (e: unknown) {
      const err = e as Error & { token?: { loc?: { line?: number; column?: number } }; loc?: { line?: number; column?: number } };
      errors.push({
        message: err.message,
        file: filePath,
        line: err.token?.loc?.line ?? err.loc?.line,
        column: err.token?.loc?.column ?? err.loc?.column,
        phase: "parser",
      });
      if (path.resolve(filePath) === entryAbs) return null;
      try {
        const entryProgram = new Parser(entrySource).parse();
        return { program: entryProgram, env: createGlobalEnvironment(), errors, warnings };
      } catch {
        return null;
      }
    }
  }

  const loopResult = runProjectTypecheckLoop(graph, programs, entryAbs, true);
  for (const e of loopResult.errors) errors.push(e);
  for (const w of loopResult.warnings) warnings.push(w);
  const { entryProgram, entryEnv } = loopResult;

  if (!entryProgram || !entryEnv) {
    const fallback = new Parser(entrySource).parse();
    return { program: fallback, env: createGlobalEnvironment(), errors, warnings };
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
