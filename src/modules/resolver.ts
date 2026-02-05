import * as path from "path";
import type * as AST from "../parser/ast";
import { Parser } from "../parser";

export type ResolveResult =
  | { kind: "local"; path: string }
  | { kind: "external" };

export interface ResolverError {
  message: string;
  file?: string;
  specifier?: string;
}

const EXTENSION_MS = ".ms";
const PKG_PREFIX = "pkg:";

function isRelative(specifier: string): boolean {
  return specifier.startsWith("./") || specifier.startsWith("../");
}

function normalizeAndResolve(
  projectRoot: string,
  srcDir: string,
  specifier: string
): string {
  const withExt = specifier.endsWith(EXTENSION_MS)
    ? specifier
    : specifier + EXTENSION_MS;
  const resolved = path.normalize(path.join(srcDir, withExt));
  return path.resolve(resolved);
}

function escapesSrcDir(resolvedPath: string, srcDir: string): boolean {
  const srcAbs = path.resolve(srcDir);
  const resolved = path.resolve(resolvedPath);
  return (
    resolved !== srcAbs && !resolved.startsWith(srcAbs + path.sep)
  );
}

export function resolveSpecifier(
  projectRoot: string,
  srcDir: string,
  specifier: string
): ResolveResult | ResolverError {
  if (isRelative(specifier)) {
    return {
      message:
        'Relative imports are not allowed; use logical paths from src root (e.g. "lib/foo").',
      specifier,
    };
  }
  if (specifier.startsWith(PKG_PREFIX)) {
    return { kind: "external" };
  }
  const resolved = normalizeAndResolve(projectRoot, srcDir, specifier);
  if (escapesSrcDir(resolved, srcDir)) {
    return {
      message: "Import path must stay under src directory.",
      specifier,
    };
  }
  return { kind: "local", path: resolved };
}

function getImportSpecifiers(program: AST.Program): { specifier: string }[] {
  const out: { specifier: string }[] = [];
  for (const stmt of program.body) {
    if (stmt.kind === "ImportDecl") {
      out.push({ specifier: stmt.source });
    }
  }
  return out;
}

export interface ModuleGraph {
  order: string[];
  specifierToPath: Map<string, Map<string, string>>;
  errors: ResolverError[];
}

export async function buildModuleGraph(
  entryPath: string,
  projectRoot: string,
  srcDir: string,
  readFile: (filePath: string) => Promise<string>
): Promise<ModuleGraph> {
  const errors: ResolverError[] = [];
  const specifierToPath = new Map<string, Map<string, string>>();
  const visited = new Set<string>();
  const stackOrder: string[] = [];
  const pathToDeps = new Map<string, string[]>();

  const entryAbs = path.resolve(entryPath);

  async function visit(filePath: string, importerPath?: string, specifier?: string): Promise<void> {
    const key = path.resolve(filePath);
    if (visited.has(key)) return;
    const stackIndex = stackOrder.indexOf(key);
    if (stackIndex !== -1) {
      const cycle = stackOrder.slice(stackIndex).concat(key);
      errors.push({
        message: `Circular dependency: ${cycle.join(" → ")}`,
        file: importerPath ?? filePath,
      });
      return;
    }
    stackOrder.push(key);
    let source: string;
    try {
      source = await readFile(filePath);
    } catch (e: unknown) {
      const err = e as NodeJS.ErrnoException;
      const msg =
        err?.code === "ENOENT"
          ? `Module not found: ${filePath}`
          : `Cannot read file: ${(e as Error).message}`;
      errors.push({ message: msg, file: importerPath ?? filePath, specifier });
      stackOrder.pop();
      return;
    }
    let program: AST.Program;
    try {
      program = new Parser(source).parse();
    } catch (e) {
      errors.push({
        message: `Parse error: ${(e as Error).message}`,
        file: filePath,
      });
      stackOrder.pop();
      return;
    }
    const imports = getImportSpecifiers(program);
    const deps: string[] = [];
    const thisMap = new Map<string, string>();
    specifierToPath.set(key, thisMap);
    for (const { specifier } of imports) {
      const result = resolveSpecifier(projectRoot, srcDir, specifier);
      if ("kind" in result) {
        if (result.kind === "local") {
          deps.push(result.path);
          thisMap.set(specifier, result.path);
        }
      } else {
        errors.push({ ...result, file: filePath });
      }
    }
    pathToDeps.set(key, deps);
    for (const [specifier, depPath] of thisMap) {
      await visit(depPath, filePath, specifier);
    }
    stackOrder.pop();
    visited.add(key);
  }

  await visit(entryAbs);

  if (errors.length > 0) {
    return { order: [], specifierToPath, errors };
  }

  const order = topologicalOrder(pathToDeps);
  return { order, specifierToPath, errors };
}

function topologicalOrder(pathToDeps: Map<string, string[]>): string[] {
  const nodes = new Set<string>();
  pathToDeps.forEach((_, n) => nodes.add(n));
  pathToDeps.forEach((deps) => deps.forEach((d) => nodes.add(path.resolve(d))));
  const inDegree = new Map<string, number>();
  for (const n of nodes) {
    inDegree.set(n, 0);
  }
  for (const [from, deps] of pathToDeps) {
    for (const d of deps) {
      const to = path.resolve(d);
      if (nodes.has(to)) {
        inDegree.set(to, (inDegree.get(to) ?? 0) + 1);
      }
    }
  }
  const queue: string[] = [];
  for (const [n, deg] of inDegree) {
    if (deg === 0) queue.push(n);
  }
  const result: string[] = [];
  while (queue.length > 0) {
    const n = queue.shift()!;
    result.push(n);
    for (const d of pathToDeps.get(n) ?? []) {
      const to = path.resolve(d);
      const deg = (inDegree.get(to) ?? 1) - 1;
      inDegree.set(to, deg);
      if (deg === 0) queue.push(to);
    }
  }
  const order = result.length === nodes.size ? result : Array.from(nodes);
  return order.reverse();
}
