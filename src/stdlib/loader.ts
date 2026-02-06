// Stdlib module loader
// In dev: reads .ms files from disk via import.meta.dir
// In compiled binary: reads from Bun.embeddedFiles (via isCompiledBinary)

import { readFileSync, readdirSync } from "fs";
import { Parser } from "../parser";
import { extractBuiltinsTypes, type BuiltinsTypes } from "../builtin/extractor";
import { TypeCheckError } from "../types/errors";
import type { TypeEnvironment } from "../types/environment";
import type * as AST from "../parser/ast";
import { isCompiledBinary } from "../shared/env";

const STDLIB_DIR = import.meta.dir;
const sourceCache = new Map<string, string>();
const astCache = new Map<string, AST.Program>();
const typesCache = new Map<string, BuiltinsTypes>();

let embeddedIndex: Map<string, Blob> | null = null;
function getEmbeddedIndex(): Map<string, Blob> {
  if (!embeddedIndex) {
    embeddedIndex = new Map();
    if (isCompiledBinary()) {
      for (const blob of Bun.embeddedFiles) {
        embeddedIndex.set((blob as { name?: string }).name ?? "", blob);
      }
    }
  }
  return embeddedIndex;
}

export async function getStdlibSource(name: string): Promise<string | null> {
  if (sourceCache.has(name)) return sourceCache.get(name)!;
  const filename = `${name}.ms`;
  const blob = getEmbeddedIndex().get(filename);
  if (blob) {
    const source = await blob.text();
    sourceCache.set(name, source);
    return source;
  }
  try {
    const source = readFileSync(`${STDLIB_DIR}/${filename}`, "utf-8");
    sourceCache.set(name, source);
    return source;
  } catch {
    return null;
  }
}

export function getStdlibSourceSync(name: string): string | null {
  if (sourceCache.has(name)) return sourceCache.get(name)!;
  try {
    const source = readFileSync(`${STDLIB_DIR}/${name}.ms`, "utf-8");
    sourceCache.set(name, source);
    return source;
  } catch {
    return null;
  }
}

export function getStdlibAST(name: string): AST.Program | null {
  if (astCache.has(name)) return astCache.get(name)!;
  const source = getStdlibSourceSync(name);
  if (!source) return null;
  const ast = new Parser(source).parse();
  astCache.set(name, ast);
  return ast;
}

export function getStdlibTypes(name: string): BuiltinsTypes | null {
  if (typesCache.has(name)) return typesCache.get(name)!;
  const ast = getStdlibAST(name);
  if (!ast) return null;
  const types = extractBuiltinsTypes(ast);
  typesCache.set(name, types);
  return types;
}

// Centralized: resolve all std/ imports and bind types into the environment
export function resolveStdlibImports(program: AST.Program, env: TypeEnvironment): TypeCheckError[] {
  const errors: TypeCheckError[] = [];
  const loc0 = { line: 0, column: 0, offset: 0 };
  for (const decl of program.body) {
    if (decl.kind !== "ImportDecl" || !isStdlibImport(decl.source)) continue;
    const modName = stdlibModuleName(decl.source);
    const stdTypes = getStdlibTypes(modName);
    if (!stdTypes) {
      errors.push(new TypeCheckError(`Stdlib module not found: "${decl.source}"`, decl.loc ?? loc0));
      continue;
    }
    if (stdTypes.builtinMethods.size > 0) {
      env.mergeBuiltinMethods(stdTypes.builtinMethods);
    }
    for (const { name, alias } of decl.names) {
      const type = stdTypes.functions.get(name) ?? stdTypes.types.get(name);
      if (!type) {
        errors.push(new TypeCheckError(`Module "${decl.source}" does not export "${name}".`, decl.loc ?? loc0));
        continue;
      }
      try {
        if (stdTypes.types.has(name)) env.defineType(alias ?? name, type);
        else env.define(alias ?? name, type, false);
      } catch {
        errors.push(new TypeCheckError(`Cannot import "${name}": shadows builtin; use an alias.`, decl.loc ?? loc0));
      }
    }
  }
  return errors;
}

// Check if a name is an extern type in any loaded stdlib module
export function isStdlibExternType(name: string): boolean {
  for (const types of typesCache.values()) {
    if (types.externTypes.has(name)) return true;
  }
  return false;
}

// Discover all available stdlib module sources (for compilation)
export function getAllStdlibSources(): Map<string, string> {
  const result = new Map<string, string>();
  // Try embedded files first (compiled binary)
  const idx = getEmbeddedIndex();
  for (const [filename] of idx) {
    if (filename.endsWith(".ms")) {
      const modName = filename.replace(/\.ms$/, "");
      const src = getStdlibSourceSync(modName);
      if (src) result.set(modName, src);
    }
  }
  if (result.size > 0) return result;
  // Fall back to disk scan (development)
  try {
    for (const file of readdirSync(STDLIB_DIR)) {
      if (file.endsWith(".ms")) {
        const modName = file.replace(/\.ms$/, "");
        const src = getStdlibSourceSync(modName);
        if (src) result.set(modName, src);
      }
    }
  } catch {}
  return result;
}

export function isStdlibImport(specifier: string): boolean {
  return specifier.startsWith("std/");
}

export function stdlibModuleName(specifier: string): string {
  return specifier.slice(4);
}
