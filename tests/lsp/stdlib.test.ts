import { describe, test, expect } from "bun:test";
import { isStdlibImport } from "../../src/shared/constants";
import {
  resolveStdlibDefinition,
  getStdlibHover,
} from "../../src/lsp/stdlib";
import {
  buildSymbolTable,
  resolveDefinition,
  findReferences,
} from "../../src/lsp";
import { Parser } from "../../src/parser";
import { TypeChecker } from "../../src/types";

function parseDocument(source: string) {
  const program = new Parser(source).parse();
  const result = new TypeChecker().check(program);
  const symbols = buildSymbolTable(program, result.env);
  return { program, env: result.env, symbols };
}

describe("LSP stdlib - isStdlibImport", () => {
  test("returns true for std/ specifiers", () => {
    expect(isStdlibImport("std/math")).toBe(true);
    expect(isStdlibImport("std/collections")).toBe(true);
    expect(isStdlibImport("std/concurrency")).toBe(true);
  });

  test("returns false for non-std specifiers", () => {
    expect(isStdlibImport("lib/foo")).toBe(false);
    expect(isStdlibImport("std")).toBe(false);
    expect(isStdlibImport("")).toBe(false);
  });
});

describe("LSP stdlib - resolveStdlibDefinition (go to definition)", () => {
  test("returns location for std/math function (extern fn) with correct range", () => {
    const loc = resolveStdlibDefinition("std/math", "ceil");
    expect(loc).not.toBeNull();
    expect(loc!.uri).toMatch(/math\.ms$/);
    expect(loc!.range.start.line).toBeGreaterThanOrEqual(0);
    expect(loc!.range.end.character).toBeGreaterThan(loc!.range.start.character);
    expect(loc!.range.end.character - loc!.range.start.character).toBe(4);
  });

  test("returns location for std/math pure function", () => {
    const loc = resolveStdlibDefinition("std/math", "abs");
    expect(loc).not.toBeNull();
    expect(loc!.uri).toMatch(/math\.ms$/);
  });

  test("returns location for std/collections function", () => {
    const loc = resolveStdlibDefinition("std/collections", "first");
    expect(loc).not.toBeNull();
    expect(loc!.uri).toMatch(/collections\.ms$/);
  });

  test("returns location for std/concurrency type", () => {
    const loc = resolveStdlibDefinition("std/concurrency", "Channel");
    expect(loc).not.toBeNull();
    expect(loc!.uri).toMatch(/concurrency\.ms$/);
  });

  test("returns null for non-stdlib specifier", () => {
    expect(resolveStdlibDefinition("lib/foo", "bar")).toBeNull();
  });

  test("returns null for non-existent module", () => {
    expect(resolveStdlibDefinition("std/nonexistent", "x")).toBeNull();
  });

  test("returns null for non-existent export", () => {
    expect(resolveStdlibDefinition("std/math", "nonexistent")).toBeNull();
  });
});

describe("LSP stdlib - getStdlibHover (hover)", () => {
  test("returns hover for std/math extern fn with full signature", () => {
    const hover = getStdlibHover("std/math", "ceil");
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("ceil");
    expect(hover!.signature).toContain("number");
    expect(hover!.signature).toMatch(/^fn ceil\(/);
  });

  test("returns hover for std/math pure function", () => {
    const hover = getStdlibHover("std/math", "abs");
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("fn abs");
    expect(hover!.signature).toContain("n: number");
  });

  test("returns hover for std/collections function", () => {
    const hover = getStdlibHover("std/collections", "first");
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("first");
  });

  test("returns hover for std/concurrency type with doc (fields or methods)", () => {
    const hover = getStdlibHover("std/concurrency", "Channel");
    expect(hover).not.toBeNull();
    expect(hover!.signature).toMatch(/type|interface/);
    expect(hover!.signature).toContain("Channel");
    expect(hover!.doc).toBeDefined();
    expect(hover!.doc!.length).toBeGreaterThan(0);
  });

  test("returns null for non-stdlib specifier", () => {
    expect(getStdlibHover("lib/foo", "bar")).toBeNull();
  });

  test("returns null for non-existent export", () => {
    expect(getStdlibHover("std/math", "nonexistent")).toBeNull();
  });
});

describe("LSP stdlib - find references (symbol table + resolveDefinition)", () => {
  test("resolveDefinition on stdlib import returns import def with importTarget", () => {
    const source = `import { ceil } from "std/math"
let x = ceil(0.1)
let y = ceil(1.2)
`;
    const { symbols } = parseDocument(source);
    const defAtUsage = resolveDefinition(symbols, 2, 10);
    expect(defAtUsage).not.toBeNull();
    expect(defAtUsage!.importTarget).toEqual({ specifier: "std/math", exportedName: "ceil" });
  });

  test("findReferences on stdlib-imported symbol returns definition and all refs", () => {
    const source = `import { ceil } from "std/math"
let x = ceil(0.1)
let y = ceil(1.2)
`;
    const { symbols } = parseDocument(source);
    const result = findReferences(symbols, 2, 10);
    expect(result).not.toBeNull();
    expect(result!.definition.importTarget).toEqual({ specifier: "std/math", exportedName: "ceil" });
    expect(result!.references.length).toBe(2);
  });

  test("findReferences with aliased stdlib import", () => {
    const source = `import { ceil as roundUp } from "std/math"
let x = roundUp(0.5)
`;
    const { symbols } = parseDocument(source);
    const result = findReferences(symbols, 2, 10);
    expect(result).not.toBeNull();
    expect(result!.definition.name).toBe("roundUp");
    expect(result!.definition.importTarget).toEqual({ specifier: "std/math", exportedName: "ceil" });
    expect(result!.references.length).toBe(1);
  });

  test("findReferences from first usage and from second usage both return same definition", () => {
    const source = `import { min } from "std/math"
let a = min(1, 2)
let b = min(3, 4)
`;
    const { symbols } = parseDocument(source);
    const fromFirst = findReferences(symbols, 2, 10);
    const fromSecond = findReferences(symbols, 3, 10);
    expect(fromFirst).not.toBeNull();
    expect(fromSecond).not.toBeNull();
    expect(fromFirst!.definition.importTarget).toEqual(fromSecond!.definition.importTarget);
    expect(fromFirst!.definition.importTarget).toEqual({ specifier: "std/math", exportedName: "min" });
    expect(fromFirst!.references.length).toBe(2);
    expect(fromSecond!.references.length).toBe(2);
  });
});

describe("LSP stdlib - hover, go-to-definition, find references (integration)", () => {
  test("stdlib import: hover shows signature, definition resolves to stdlib module, find refs returns all usages", () => {
    const source = `import { floor } from "std/math"
let x = floor(1.5)
`;
    const { symbols } = parseDocument(source);

    const hover = getStdlibHover("std/math", "floor");
    expect(hover).not.toBeNull();
    expect(hover!.signature).toMatch(/floor/);
    expect(hover!.signature).toMatch(/number/);

    const defLoc = resolveStdlibDefinition("std/math", "floor");
    expect(defLoc).not.toBeNull();
    expect(defLoc!.uri).toMatch(/math\.ms$/);
    expect(defLoc!.range.start.line).toBeGreaterThanOrEqual(0);

    const refs = findReferences(symbols, 2, 10);
    expect(refs).not.toBeNull();
    expect(refs!.definition.importTarget).toEqual({ specifier: "std/math", exportedName: "floor" });
    expect(refs!.references).toHaveLength(1);
    expect(refs!.references[0]!.loc.line).toBe(2);
  });
});
