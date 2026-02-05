import { describe, test, expect } from "bun:test";
import { getDocumentSymbols, getTopLevelSymbols } from "../../src/lsp/document-symbols";
import { buildSymbolTable } from "../../src/lsp/symbol-builder";
import { Parser } from "../../src/parser";
import { TypeChecker } from "../../src/types";

describe("LSP Document Symbols", () => {
  test("getDocumentSymbols returns top-level functions and types with members", () => {
    const source = `
fn foo(): number
  return 0
type Person
  name: string
  fn greet(): string
`;
    const program = new Parser(source).parse();
    const checker = new TypeChecker();
    const result = checker.check(program);
    const symbols = buildSymbolTable(program, result.env);
    const docSymbols = getDocumentSymbols(symbols);
    expect(docSymbols.some((s) => s.name === "foo" && s.kind === "function")).toBe(true);
    expect(docSymbols.some((s) => s.name === "Person" && s.kind === "type")).toBe(true);
    expect(docSymbols.some((s) => s.name === "name" && s.kind === "field")).toBe(true);
    expect(docSymbols.some((s) => s.name === "greet" && s.kind === "method")).toBe(true);
    const nameSymbol = docSymbols.find((s) => s.name === "name");
    expect(nameSymbol?.parent).toBe("Person");
  });

  test("getTopLevelSymbols returns only functions and types without dot in name", () => {
    const source = `
fn bar(): void
  let x = 1
type T
  x: number
`;
    const program = new Parser(source).parse();
    const checker = new TypeChecker();
    const result = checker.check(program);
    const symbols = buildSymbolTable(program, result.env);
    const topLevel = getTopLevelSymbols(symbols);
    expect(topLevel.every((s) => s.kind === "function" || s.kind === "type")).toBe(true);
    expect(topLevel.every((s) => !s.name.includes("."))).toBe(true);
    expect(topLevel.some((s) => s.name === "bar")).toBe(true);
    expect(topLevel.some((s) => s.name === "T")).toBe(true);
    expect(topLevel.find((s) => s.name === "x")).toBeUndefined();
  });

  test("getDocumentSymbols includes interfaces and interface methods", () => {
    const source = `
interface Greeter
  fn greet(): string
type Person
  name: string
`;
    const program = new Parser(source).parse();
    const checker = new TypeChecker();
    const result = checker.check(program);
    const symbols = buildSymbolTable(program, result.env);
    const docSymbols = getDocumentSymbols(symbols);
    expect(docSymbols.some((s) => s.name === "Greeter" && s.kind === "type")).toBe(true);
    expect(docSymbols.some((s) => s.name === "greet" && s.kind === "method" && s.parent === "Greeter")).toBe(true);
    expect(docSymbols.some((s) => s.name === "Person" && s.kind === "type")).toBe(true);
  });
});
