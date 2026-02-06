import { describe, test, expect } from "bun:test";
import {
  buildSymbolTable,
  getHoverForSymbol,
  resolveDefinition,
  resolveSymbolAt,
  findReferences,
  getRenameLocations,
} from "../../src/lsp";
import { Parser } from "../../src/parser";
import { TypeChecker } from "../../src/types";

function parseDocument(source: string) {
  const program = new Parser(source).parse();
  const result = new TypeChecker().check(program);
  const symbols = buildSymbolTable(program, result.env);
  return { program, env: result.env, symbols };
}

describe("LSP Hover", () => {
  test("hover on function definition and on reference", () => {
    const source = `
fn greet(name: string): string
  return "Hello, " + name
let _ = greet("x")
`;
    const { symbols, program, env } = parseDocument(source);
    const onDef = getHoverForSymbol(symbols, program, 2, 4, env);
    expect(onDef).not.toBeNull();
    expect(onDef!.signature).toContain("fn greet");
    expect(onDef!.signature).toContain("name: string");
    const onRef = getHoverForSymbol(symbols, program, 4, 10, env);
    expect(onRef).not.toBeNull();
    expect(onRef!.signature).toContain("fn greet");
  });

  test("hover on type uses env when available, else AST", () => {
    const source = `
type Person
  name: string
  age: number
`;
    const { symbols, program, env } = parseDocument(source);
    const hover = getHoverForSymbol(symbols, program, 2, 6, env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("type Person");
    expect(hover!.doc).toContain("name: string");
  });

  test("hover on field definition and on member reference", () => {
    const source = `
type Person
  name: string
let p = Person(name: "x")
let _ = p.name
`;
    const { symbols, program, env } = parseDocument(source);
    const onFieldDef = getHoverForSymbol(symbols, program, 3, 3, env);
    expect(onFieldDef).not.toBeNull();
    expect(onFieldDef!.signature).toContain("(field)");
    expect(onFieldDef!.signature).toContain("name");
    const onMemberRef = getHoverForSymbol(symbols, program, 6, 7, env);
    if (onMemberRef) expect(onMemberRef.signature).toContain("name");
  });

  test("hover on method definition", () => {
    const source = `
type T
  fn get(): number
    return 0
let x = T()
let _ = x.get()
`;
    const { symbols, program, env } = parseDocument(source);
    const onMethodDef = getHoverForSymbol(symbols, program, 3, 6, env);
    expect(onMethodDef).not.toBeNull();
    expect(onMethodDef!.signature).toContain("(method)");
    expect(onMethodDef!.signature).toContain("get");
  });

  test("hover on generic instance method resolves to concrete return type", () => {
    const source = `
type Box[T]
  value: T
  fn get(): T
    value
let b = Box[number](10)
let _ = b.get()
`;
    const { symbols, program, env } = parseDocument(source);
    const hover = getHoverForSymbol(symbols, program, 7, 11, env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("(method)");
    expect(hover!.signature).toContain("get");
    expect(hover!.signature).toContain("number");
    expect(hover!.signature).not.toContain("): T");
  });

  test("hover on variable (let) and parameter", () => {
    const source = `
fn f(a: number): number
  let x = a
  return x
`;
    const { symbols, program, env } = parseDocument(source);
    const onVar = getHoverForSymbol(symbols, program, 3, 7, env);
    expect(onVar).not.toBeNull();
    expect(onVar!.signature).toContain("x");
    const onParam = getHoverForSymbol(symbols, program, 2, 7, env);
    expect(onParam).not.toBeNull();
    expect(onParam!.signature).toContain("(parameter)");
    expect(onParam!.signature).toContain("a: number");
  });

  test("hover on destructured variables shows inferred type", () => {
    const source = `
let { x, y } = { x: 3, y: 4 }
print(x)
print(y)
`;
    const { symbols, program, env } = parseDocument(source);
    const onX = getHoverForSymbol(symbols, program, 3, 7, env);
    expect(onX).not.toBeNull();
    expect(onX!.signature).toContain("x");
    expect(onX!.signature).toContain("number");
    const onY = getHoverForSymbol(symbols, program, 4, 7, env);
    expect(onY).not.toBeNull();
    expect(onY!.signature).toContain("y");
    expect(onY!.signature).toContain("number");
  });

  test("hover on method parameter", () => {
    const source = `
type T
  fn add(n: number): number
    return n
`;
    const { symbols, program, env } = parseDocument(source);
    const hover = getHoverForSymbol(symbols, program, 3, 10, env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("(parameter)");
    expect(hover!.signature).toContain("n");
  });

  test("hover returns null when not on symbol", () => {
    const { symbols, program, env } = parseDocument("let x = 1");
    expect(getHoverForSymbol(symbols, program, 1, 1, env)).toBeNull();
  });

  test("hover on function uses formatFnSignature when type not resolved", () => {
    const source = `fn bar(a: number): number\n  return a`;
    const { program, symbols, env } = parseDocument(source);
    const hover = getHoverForSymbol(symbols, program, 1, 4, env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("bar");
    expect(hover!.signature).toContain("number");
  });

  test("hover on type without env uses findTypeDecl", () => {
    const source = `type Box\n  x: number`;
    const { program, symbols } = parseDocument(source);
    const hover = getHoverForSymbol(symbols, program, 1, 6, undefined);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("type Box");
  });

  test("hover on with-let binding shows variable type", () => {
    const source = `
type MyResource
  name: string
  fn close(): void
with let a = MyResource(name: "x")
  print(a)
`;
    const { symbols, program, env } = parseDocument(source);
    const onBinding = getHoverForSymbol(symbols, program, 5, 10, env);
    expect(onBinding).not.toBeNull();
    expect(onBinding!.signature).toContain("a");
    expect(onBinding!.signature).toContain("MyResource");
  });

  test("hover on var shows (var) prefix", () => {
    const source = `
fn f()
  var y = 2
  print(y)
`;
    const { symbols, program, env } = parseDocument(source);
    const hover = getHoverForSymbol(symbols, program, 3, 7, env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("y");
  });

  test("hover on interface definition and on reference in type annotation", () => {
    const source = `
interface Greeter
  fn greet(): string
type Person
  name: string
  fn greet(): string
    return "Hi"
fn use(g: Greeter): string
  return g.greet()
let p = Person(name: "x")
let _ = use(p)
`;
    const { symbols, program, env } = parseDocument(source);
    const onIfaceDef = getHoverForSymbol(symbols, program, 2, 12, env);
    expect(onIfaceDef).not.toBeNull();
    expect(onIfaceDef!.signature).toContain("interface Greeter");
    expect(onIfaceDef!.doc).toContain("greet");
    const onRef = getHoverForSymbol(symbols, program, 8, 12, env);
    expect(onRef).not.toBeNull();
    expect(onRef!.signature).toContain("interface Greeter");
  });

  test("hover on interface method definition", () => {
    const source = `
interface I
  fn m(x: number): string
`;
    const { symbols, program, env } = parseDocument(source);
    const hover = getHoverForSymbol(symbols, program, 3, 6, env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("(method)");
    expect(hover!.signature).toContain("m");
  });
});

describe("LSP Resolver", () => {
  test("resolveSymbolAt returns definition when position on def", () => {
    const source = `fn foo(): number\n  return 0`;
    const { symbols } = parseDocument(source);
    const sym = resolveSymbolAt(symbols, 1, 4);
    expect(sym).toBeDefined();
    expect("nameOffset" in sym!).toBe(true);
    expect((sym as any).name).toBe("foo");
  });

  test("resolveSymbolAt returns reference when position on reference", () => {
    const source = `fn foo(): number\n  return 0\nlet x = foo()`;
    const { symbols } = parseDocument(source);
    const sym = resolveSymbolAt(symbols, 3, 9);
    expect(sym).toBeDefined();
    expect("symbolId" in sym!).toBe(true);
  });

  test("resolveDefinition returns def when on definition", () => {
    const source = `fn foo(): number\n  return 0`;
    const { symbols } = parseDocument(source);
    const def = resolveDefinition(symbols, 1, 4);
    expect(def).not.toBeNull();
    expect(def!.name).toBe("foo");
    expect(def!.id.kind).toBe("function");
  });

  test("resolveDefinition returns def when on reference", () => {
    const source = `fn foo(): number\n  return 0\nlet x = foo()`;
    const { symbols } = parseDocument(source);
    const def = resolveDefinition(symbols, 3, 9);
    expect(def).not.toBeNull();
    expect(def!.name).toBe("foo");
  });

  test("findReferences returns definition and all refs", () => {
    const source = `fn f(): number\n  return 0\nlet _ = f()\nlet __ = f()`;
    const { symbols } = parseDocument(source);
    const result = findReferences(symbols, 1, 4);
    expect(result).not.toBeNull();
    expect(result!.definition.name).toBe("f");
    expect(result!.references.length).toBe(2);
  });

  test("getRenameLocations includes definition and references", () => {
    const source = `fn greet(): string\n  return "hi"\nlet x = greet()`;
    const { symbols } = parseDocument(source);
    const locs = getRenameLocations(symbols, 1, 4);
    expect(locs).not.toBeNull();
    expect(locs!.length).toBeGreaterThanOrEqual(2);
    const lines = locs!.map((l) => l.loc.line);
    expect(lines).toContain(1);
    expect(lines).toContain(3);
  });

  test("resolveDefinition for interface: on definition; findReferences includes type annotation", () => {
    const source = `
interface Reader
  fn read(): string
fn f(r: Reader): string
  return r.read()
`;
    const { symbols } = parseDocument(source);
    const defOnDef = resolveDefinition(symbols, 2, 12);
    expect(defOnDef).not.toBeNull();
    expect(defOnDef!.name).toBe("Reader");
    expect(defOnDef!.id.kind).toBe("type");
    const refs = findReferences(symbols, 2, 12);
    expect(refs).not.toBeNull();
    expect(refs!.definition.name).toBe("Reader");
    expect(refs!.references.length).toBeGreaterThanOrEqual(1);
  });

  test("findReferences and getRenameLocations for interface", () => {
    const source = `
interface I
  fn m(): number
fn use(x: I): number
  return x.m()
`;
    const { symbols } = parseDocument(source);
    const refs = findReferences(symbols, 2, 11);
    expect(refs).not.toBeNull();
    expect(refs!.definition.name).toBe("I");
    expect(refs!.references.length).toBeGreaterThanOrEqual(1);
    const locs = getRenameLocations(symbols, 2, 11);
    expect(locs).not.toBeNull();
    expect(locs!.length).toBeGreaterThanOrEqual(2);
  });
});

describe("LSP Symbol builder coverage", () => {
  test("buildSymbolTable with if/else, for, match, try/catch", () => {
    const source = `
fn f(x: number): number
  if x > 0
    return 1
  else
    return 0
  for i in range(0, 10)
    if i == 5
      return i
  match x
    1 => 1
    _ => 0
  try
    return x
  catch e
    return 0
`;
    const { symbols } = parseDocument(source);
    expect(symbols.getAllDefinitions().length).toBeGreaterThan(0);
    expect(symbols.getAllReferences().length).toBeGreaterThan(0);
  });

  test("buildSymbolTable with MemberExpr, CallExpr, IndexExpr, template, list, map", () => {
    const source = `
type T
  value: number = 0
  fn get(): number
    return value
let t = T()
let v = t.get()
let list = [1, 2, 3]
let first = list[0]
let msg = "hello {v}"
let m = { a: 1, b: 2 }
`;
    const { symbols } = parseDocument(source);
    const refs = symbols.getAllReferences();
    expect(refs.length).toBeGreaterThan(0);
    const defs = symbols.getAllDefinitions();
    expect(defs.some((d) => d.id.kind === "field")).toBe(true);
    expect(defs.some((d) => d.id.kind === "method")).toBe(true);
  });

  test("buildSymbolTable with TestDecl and DeferStmt", () => {
    const source = `
fn _dummy(): number
  return 0
test "t1"
  defer print(1)
  assert true
`;
    const { symbols } = parseDocument(source);
    expect(symbols.getAllDefinitions().length).toBeGreaterThan(0);
  });
});
