import { describe, test, expect, beforeEach } from "bun:test";
import { Parser } from "../../src/parser";
import { TypeChecker } from "../../src/types/checker";
import type { Program, FnDecl, TypeDecl } from "../../src/parser/ast";
import type { Type } from "../../src/types/types";
import type { TypeEnvironment } from "../../src/types/environment";
import { buildSymbolTable, resolveDefinition, findReferences, getRenameLocations, getHoverForSymbol, getDocumentSymbols, getObjectMemberCompletions, type SymbolTable } from "../../src/lsp";
import { resolveObjectType } from "../../src/types/type-utils";

// Test helpers that mirror server.ts logic
const KEYWORDS = [
  "fn", "type", "let", "var", "if", "else", "for", "match", "return",
  "using", "with", "import", "from", "test", "yield", "defer", "try",
  "catch", "throw", "break", "continue", "spawn", "extends",
  "and", "or", "not", "is", "as", "then", "in", "true", "false", "null", "where"
];

const BUILTIN_TYPES = [
  "number", "string", "bool", "null", "bytes", "unknown", "never", "void",
  "list", "map", "set", "Promise", "Stream", "Result"
];

const BUILTIN_FUNCTIONS = [
  "print", "len", "range", "clone", "keys", "values", "entries",
  "floor", "ceil", "round", "abs", "min", "max", "sum",
  "int", "float", "str", "type_of", "assert"
];

function formatTypeExpr(type: any): string {
  if (!type) return "unknown";
  switch (type.kind) {
    case "NamedType": return type.name;
    case "GenericType": return `${type.name}[${type.args.map(formatTypeExpr).join(", ")}]`;
    case "FunctionType": return `fn(${type.params.map(formatTypeExpr).join(", ")}): ${formatTypeExpr(type.returnType)}`;
    case "UnionType": return type.types.map(formatTypeExpr).join(" or ");
    case "OptionalType": return `${formatTypeExpr(type.inner)}?`;
    case "ListType": return `list[${formatTypeExpr(type.elementType)}]`;
    default: return "unknown";
  }
}

interface DocumentCache {
  program: Program;
  env: TypeEnvironment;
  symbols: SymbolTable;
}

function parseDocument(source: string): DocumentCache | null {
  try {
    const parser = new Parser(source);
    const program = parser.parse();
    const checker = new TypeChecker();
    const result = checker.check(program);
    const symbols = buildSymbolTable(program, result.env);
    return { program, env: result.env, symbols };
  } catch {
    return null;
  }
}

function getWordAtPosition(text: string, line: number, col: number): { word: string; isProperty: boolean } {
  const lines = text.split("\n");
  const lineText = lines[line] || "";
  const before = lineText.slice(0, col);
  const after = lineText.slice(col);
  const wordStart = before.match(/[a-zA-Z_][a-zA-Z0-9_]*$/)?.[0] || "";
  const wordEnd = after.match(/^[a-zA-Z0-9_]*/)?.[0] || "";
  const word = wordStart + wordEnd;
  const beforeWord = before.slice(0, before.length - wordStart.length);
  const isProperty = beforeWord.trimEnd().endsWith(".");
  return { word, isProperty };
}

function collectSymbols(program: Program): { name: string; kind: string; line: number }[] {
  const symbols: { name: string; kind: string; line: number }[] = [];
  
  for (const stmt of program.body) {
    if (stmt.kind === "FnDecl") {
      symbols.push({ name: (stmt as FnDecl).name, kind: "function", line: stmt.loc.line });
    } else if (stmt.kind === "TypeDecl") {
      symbols.push({ name: (stmt as TypeDecl).name, kind: "type", line: stmt.loc.line });
    } else if (stmt.kind === "TestDecl") {
      symbols.push({ name: `test "${(stmt as any).name}"`, kind: "test", line: stmt.loc.line });
    }
  }
  return symbols;
}

describe("VSCode Extension - Document Parsing", () => {
  test("parses valid manuscript code", () => {
    const source = `
fn add(a: number, b: number): number
  return a + b
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    expect(cached!.program.body.length).toBe(1);
    expect(cached!.program.body[0]!.kind).toBe("FnDecl");
  });

  test("handles parse errors gracefully", () => {
    const source = `fn invalid(`;
    const cached = parseDocument(source);
    expect(cached).toBeNull();
  });

  test("parses type declarations", () => {
    const source = `
type Person
  name: string
  age: number
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    const typeDecl = cached!.program.body[0] as TypeDecl;
    expect(typeDecl.kind).toBe("TypeDecl");
    expect(typeDecl.name).toBe("Person");
  });

  test("parses test blocks", () => {
    const source = `
test "addition works"
  assert(1 + 1 == 2)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    expect(cached!.program.body[0]!.kind).toBe("TestDecl");
  });
});

describe("VSCode Extension - Type Checking", () => {
  test("type checks function with correct types", () => {
    const source = `
fn greet(name: string): string
  return "Hello, " + name
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
  });

  test("detects type errors", () => {
    const source = `
fn bad(): number
  return "not a number"
`;
    const parser = new Parser(source);
    const program = parser.parse();
    const checker = new TypeChecker();
    const result = checker.check(program);
    expect(result.errors.length).toBeGreaterThan(0);
  });
});

describe("VSCode Extension - Document Symbols", () => {
  test("extracts function symbols", () => {
    const source = `
fn foo()
  print("foo")

fn bar(x: number): number
  return x * 2
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    const symbols = collectSymbols(cached!.program);
    expect(symbols).toContainEqual({ name: "foo", kind: "function", line: 2 });
    expect(symbols).toContainEqual({ name: "bar", kind: "function", line: 5 });
  });

  test("extracts type symbols", () => {
    const source = `
type Point
  x: number
  y: number

type Rectangle
  width: number
  height: number
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    const symbols = collectSymbols(cached!.program);
    expect(symbols.filter(s => s.kind === "type")).toHaveLength(2);
  });

  test("extracts test symbols", () => {
    const source = `
test "math works"
  assert(1 + 1 == 2)

test "strings work"
  assert("a" + "b" == "ab")
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    const symbols = collectSymbols(cached!.program);
    expect(symbols.filter(s => s.kind === "test")).toHaveLength(2);
  });
});

describe("VSCode Extension - Word Detection", () => {
  test("detects word at cursor position", () => {
    const text = "let foo = 42";
    const { word, isProperty } = getWordAtPosition(text, 0, 5);
    expect(word).toBe("foo");
    expect(isProperty).toBe(false);
  });

  test("detects property access", () => {
    const text = "user.name";
    const { word, isProperty } = getWordAtPosition(text, 0, 7);
    expect(word).toBe("name");
    expect(isProperty).toBe(true);
  });

  test("handles cursor at word boundaries", () => {
    const text = "hello world";
    const start = getWordAtPosition(text, 0, 0);
    expect(start.word).toBe("hello");
    
    const end = getWordAtPosition(text, 0, 5);
    expect(end.word).toBe("hello");
    
    const nextWord = getWordAtPosition(text, 0, 6);
    expect(nextWord.word).toBe("world");
  });
});

describe("VSCode Extension - Completion", () => {
  test("KEYWORDS list is complete", () => {
    expect(KEYWORDS).toContain("fn");
    expect(KEYWORDS).toContain("type");
    expect(KEYWORDS).toContain("if");
    expect(KEYWORDS).toContain("else");
    expect(KEYWORDS).toContain("for");
    expect(KEYWORDS).toContain("match");
    expect(KEYWORDS).toContain("return");
    expect(KEYWORDS).toContain("let");
    expect(KEYWORDS).toContain("var");
  });

  test("BUILTIN_TYPES list is complete", () => {
    expect(BUILTIN_TYPES).toContain("number");
    expect(BUILTIN_TYPES).toContain("string");
    expect(BUILTIN_TYPES).toContain("bool");
    expect(BUILTIN_TYPES).toContain("list");
    expect(BUILTIN_TYPES).toContain("map");
  });

  test("BUILTIN_FUNCTIONS list is complete", () => {
    expect(BUILTIN_FUNCTIONS).toContain("print");
    expect(BUILTIN_FUNCTIONS).toContain("len");
    expect(BUILTIN_FUNCTIONS).toContain("range");
    expect(BUILTIN_FUNCTIONS).toContain("assert");
  });
});

describe("VSCode Extension - Type Formatting", () => {
  test("formats named types", () => {
    const type = { kind: "NamedType", name: "string" };
    expect(formatTypeExpr(type)).toBe("string");
  });

  test("formats generic types", () => {
    const type = {
      kind: "GenericType",
      name: "list",
      args: [{ kind: "NamedType", name: "number" }]
    };
    expect(formatTypeExpr(type)).toBe("list[number]");
  });

  test("formats union types", () => {
    const type = {
      kind: "UnionType",
      types: [
        { kind: "NamedType", name: "string" },
        { kind: "NamedType", name: "number" }
      ]
    };
    expect(formatTypeExpr(type)).toBe("string or number");
  });

  test("formats optional types", () => {
    const type = {
      kind: "OptionalType",
      inner: { kind: "NamedType", name: "string" }
    };
    expect(formatTypeExpr(type)).toBe("string?");
  });

  test("handles null/undefined types", () => {
    expect(formatTypeExpr(null)).toBe("unknown");
    expect(formatTypeExpr(undefined)).toBe("unknown");
  });
});

describe("VSCode Extension - Hover Information", () => {
  test("generates hover for function declaration", () => {
    const source = `
fn greet(name: string, age: number): string
  return "Hello"
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const fn = cached!.program.body[0] as FnDecl;
    const params = fn.params.map(p => `${p.name}: ${p.type ? formatTypeExpr(p.type) : "unknown"}`).join(", ");
    const ret = fn.returnType ? formatTypeExpr(fn.returnType) : "unknown";
    
    expect(params).toBe("name: string, age: number");
    expect(ret).toBe("string");
  });

  test("infers variable types from value", () => {
    const source = `
let x = 42
let y = "hello"
let z = true
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // Check that let statements have their values type-checked
    const letStmts = cached!.program.body.filter(s => s.kind === "LetStmt");
    expect(letStmts).toHaveLength(3);
    
    // Get inferred types from the type checker
    for (const stmt of letStmts) {
      const value = (stmt as any).value;
      const inferredType = value.resolvedType;
      expect(inferredType).toBeDefined();
    }
  });

  test("infers function parameter types", () => {
    const source = `
fn add(a: number, b: number): number
  return a + b
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const fn = cached!.program.body[0] as FnDecl;
    expect(fn.params[0]?.type).toBeDefined();
    expect(formatTypeExpr(fn.params[0]?.type)).toBe("number");
  });

  test("infers list literal types correctly", () => {
    const source = `
let nums = [1, 2, 3]
let strs = ["a", "b"]
let mixed = [1, "two"]
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const letStmts = cached!.program.body.filter(s => s.kind === "LetStmt") as any[];
    expect(letStmts).toHaveLength(3);
    
    // Check nums is list[number]
    const numsType = letStmts[0].value.resolvedType;
    expect(numsType?.kind).toBe("list");
    expect((numsType as any).elementType.kind).toBe("number");
    
    // Check strs is list[string]
    const strsType = letStmts[1].value.resolvedType;
    expect(strsType?.kind).toBe("list");
    expect((strsType as any).elementType.kind).toBe("string");
  });

  test("infers for loop variable type from iterable", () => {
    const source = `
fn sum_list(items: list[number]): number
  var total = 0
  for item in items
    total = total + item
  return total
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // The iterable 'items' should be typed as list[number]
    const fn = cached!.program.body[0] as FnDecl;
    const forStmt = fn.body?.statements?.find(s => s.kind === "ForStmt") as any;
    expect(forStmt).toBeDefined();
    
    // Check iterable type was inferred
    const iterType = forStmt.iterable.resolvedType;
    expect(iterType?.kind).toBe("list");
  });

  test("infers type from object construction", () => {
    const source = `
type Point
  x: number
  y: number

let p = Point(x: 1, y: 2)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const letStmt = cached!.program.body.find(s => s.kind === "LetStmt") as any;
    expect(letStmt).toBeDefined();
    
    const valueType = letStmt.value.resolvedType;
    expect(valueType).toBeDefined();
    expect(valueType?.kind).toBe("object");
  });
});

describe("VSCode Extension - Complex Documents", () => {
  test("parses document with type and functions", () => {
    const source = `
type User
  name: string
  email: string

fn get_name(u: User): string
  return u.name
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const symbols = collectSymbols(cached!.program);
    expect(symbols).toHaveLength(2);
  });

  test("parses document with methods", () => {
    const source = `
type Counter
  value: number = 0
  
  fn increment()
    value = value + 1
  
  fn get(): number
    return value
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const typeDecl = cached!.program.body[0] as any;
    // 1 field + 2 methods = 3 members
    expect(typeDecl.body.members).toHaveLength(3);
  });

  test("parses function with optional return", () => {
    const source = `
fn maybe_value(flag: bool): number?
  if flag
    return 42
  return null
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
  });
});

describe("VSCode Extension - Error Handling", () => {
  test("extracts error location from message", () => {
    const errorMsg = "Unexpected token at line 5, column 10";
    const match = errorMsg.match(/at line (\d+), column (\d+)/);
    expect(match).not.toBeNull();
    expect(parseInt(match![1]!)).toBe(5);
    expect(parseInt(match![2]!)).toBe(10);
  });

  test("cleans error messages for display", () => {
    const errorMsg = "Type error: expected number but got string at line 3, column 5";
    const cleaned = errorMsg.replace(/ at line \d+, column \d+$/, "");
    expect(cleaned).toBe("Type error: expected number but got string");
  });
});

describe("VSCode Extension - Indentation-based Parsing", () => {
  test("correctly parses nested blocks", () => {
    const source = `
fn factorial(n: number): number
  if n <= 1
    return 1
  return n * factorial(n - 1)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const fn = cached!.program.body[0] as FnDecl;
    expect(fn.body?.statements).toHaveLength(2);
  });

  test("handles for loops", () => {
    const source = `
fn sum_list(items: list[number]): number
  var total = 0
  for item in items
    total = total + item
  return total
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
  });

  test("handles match expressions", () => {
    const source = `
fn describe(n: number): string
  return match n
    0 => "zero"
    1 => "one"
    _ => "many"
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
  });
});

describe("VSCode Extension - Keyword Recognition", () => {
  test("identifies all control flow keywords", () => {
    const controlKeywords = ["if", "else", "for", "match", "return", "break", "continue", "yield"];
    for (const kw of controlKeywords) {
      expect(KEYWORDS).toContain(kw);
    }
  });

  test("identifies all declaration keywords", () => {
    const declKeywords = ["fn", "type", "let", "var", "test"];
    for (const kw of declKeywords) {
      expect(KEYWORDS).toContain(kw);
    }
  });

  test("identifies operator keywords", () => {
    const opKeywords = ["and", "or", "not", "is", "as", "in"];
    for (const kw of opKeywords) {
      expect(KEYWORDS).toContain(kw);
    }
  });
});

import { collectSymbols as collectAllSymbols, findScope } from "../../src/types/ast-visitor";

describe("VSCode Extension - Go to Definition", () => {
  test("finds function definition", () => {
    const source = `
fn greet(name: string): string
  return "Hello, " + name

fn main()
  print(greet("World"))
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const syms = collectAllSymbols(cached!.program);
    const fnSym = syms.find(s => s.name === "greet" && s.kind === "function");
    expect(fnSym).toBeDefined();
    expect(fnSym!.loc.line).toBe(2);
  });

  test("finds type definition", () => {
    const source = `
type Person
  name: string
  age: number

fn create(): Person
  return Person(name: "John", age: 30)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const syms = collectAllSymbols(cached!.program);
    const typeSym = syms.find(s => s.name === "Person" && s.kind === "type");
    expect(typeSym).toBeDefined();
    expect(typeSym!.loc.line).toBe(2);
  });

  test("finds type field definition", () => {
    const source = `
type Person
  name: string
  age: number
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const syms = collectAllSymbols(cached!.program);
    const fieldSym = syms.find(s => s.name === "name" && s.kind === "field");
    expect(fieldSym).toBeDefined();
    expect(fieldSym!.scope).toBe("Person");
    expect(fieldSym!.loc.line).toBe(3);
  });

  test("finds type method definition", () => {
    const source = `
type Counter
  value: number = 0

  fn increment()
    value = value + 1

  fn get(): number
    return value
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const syms = collectAllSymbols(cached!.program);
    const methodSym = syms.find(s => s.name === "increment" && s.kind === "method");
    expect(methodSym).toBeDefined();
    expect(methodSym!.scope).toBe("Counter");
    expect(methodSym!.loc.line).toBe(5);
  });

  test("finds parameter definition in function", () => {
    const source = `
fn greet(name: string, age: number): string
  return "Hello, " + name
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const syms = collectAllSymbols(cached!.program);
    const paramSym = syms.find(s => s.name === "name" && s.kind === "parameter");
    expect(paramSym).toBeDefined();
    expect(paramSym!.scope).toBe("greet");
  });

  test("finds variable definition", () => {
    const source = `
let x = 42
var y = "hello"

fn main()
  print(x)
  print(y)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const syms = collectAllSymbols(cached!.program);
    const letSym = syms.find(s => s.name === "x" && s.kind === "variable" && s.scope === "");
    expect(letSym).toBeDefined();
    
    const varSym = syms.find(s => s.name === "y" && s.kind === "variable" && s.scope === "");
    expect(varSym).toBeDefined();
  });

  test("finds scope correctly inside method", () => {
    const source = `
type Counter
  value: number = 0

  fn increment()
    value = value + 1
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // Line 6 is inside the increment method
    const scope = findScope(cached!.program, 6);
    expect(scope.scope).toBe("Counter.increment");
    expect(scope.typeName).toBe("Counter");
  });

  test("finds member definition from object type", () => {
    const source = `
type Person
  name: string
  age: number

let p = Person(name: "John", age: 30)
let n = p.name
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // Find the 'name' field in Person type
    const syms = collectAllSymbols(cached!.program);
    const fieldSym = syms.find(s => s.name === "name" && s.kind === "field" && s.scope === "Person");
    expect(fieldSym).toBeDefined();
    expect(fieldSym!.loc.line).toBe(3);
    
    // Verify field can be found by searching type declarations
    for (const s of cached!.program.body) {
      if (s.kind === "TypeDecl" && s.name === "Person") {
        const member = s.body?.members?.find(m => m.name === "name");
        expect(member).toBeDefined();
        expect(member!.kind).toBe("FieldDecl");
      }
    }
  });

  test("finds method definition from object type", () => {
    const source = `
type Calculator
  value: number = 0

  fn add(n: number): number
    value = value + n
    return value

  fn reset()
    value = 0

let calc = Calculator()
let result = calc.add(5)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // Find the 'add' method in Calculator type
    const syms = collectAllSymbols(cached!.program);
    const methodSym = syms.find(s => s.name === "add" && s.kind === "method" && s.scope === "Calculator");
    expect(methodSym).toBeDefined();
    expect(methodSym!.loc.line).toBe(5);
    
    // Verify method can be found by searching type declarations
    for (const s of cached!.program.body) {
      if (s.kind === "TypeDecl" && s.name === "Calculator") {
        const member = s.body?.members?.find(m => m.name === "add");
        expect(member).toBeDefined();
        expect(member!.kind).toBe("MethodDecl");
      }
    }
  });

  test("finds local variable in function scope", () => {
    const source = `
fn process(items: list[number]): number
  let total = 0
  for item in items
    total = total + item
  return total
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const syms = collectAllSymbols(cached!.program);
    
    // Find local variable 'total' in function scope
    const totalSym = syms.find(s => s.name === "total" && s.kind === "variable" && s.scope === "process");
    expect(totalSym).toBeDefined();
    expect(totalSym!.loc.line).toBe(3);
    
    // Find for loop variable 'item' in function scope
    const itemSym = syms.find(s => s.name === "item" && s.kind === "variable" && s.scope === "process");
    expect(itemSym).toBeDefined();
  });

  test("finds parameter in method scope", () => {
    const source = `
type Counter
  value: number = 0

  fn add(amount: number)
    value = value + amount
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const syms = collectAllSymbols(cached!.program);
    
    // Parameter 'amount' should be in scope "Counter.add"
    const paramSym = syms.find(s => s.name === "amount" && s.kind === "parameter" && s.scope === "Counter.add");
    expect(paramSym).toBeDefined();
  });
});

import { visit, visitWithScope } from "../../src/types/ast-visitor";

describe("VSCode Extension - Find References", () => {
  test("finds all references to a function", () => {
    const source = `
fn helper(x: number): number
  return x * 2

fn main()
  let a = helper(1)
  let b = helper(2)
  print(helper(3))
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const refs: { line: number; name: string }[] = [];
    visitWithScope(cached!.program, {
      onIdent(name, loc) {
        if (name === "helper") {
          refs.push({ line: loc.line, name });
        }
      },
    });
    
    // Should find 3 references to 'helper' (lines 6, 7, 8)
    expect(refs.length).toBe(3);
    expect(refs.map(r => r.line)).toContain(6);
    expect(refs.map(r => r.line)).toContain(7);
    expect(refs.map(r => r.line)).toContain(8);
  });

  test("finds all references to a type in expressions", () => {
    const source = `
type Point
  x: number
  y: number

fn create(): Point
  return Point(x: 0, y: 0)

let p = Point(x: 1, y: 2)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const refs: { line: number; name: string }[] = [];
    visitWithScope(cached!.program, {
      onIdent(name, loc) {
        if (name === "Point") {
          refs.push({ line: loc.line, name });
        }
      },
    });
    
    // Should find references to 'Point' as constructor calls (lines 7 and 9)
    // Note: type annotations are not visited by visitWithScope.onIdent
    expect(refs.length).toBe(2);
    expect(refs.map(r => r.line)).toContain(7);
    expect(refs.map(r => r.line)).toContain(9);
  });

  test("finds all member references", () => {
    const source = `
type Person
  name: string
  age: number

let p = Person(name: "John", age: 30)
print(p.name)
print(p.age)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const memberRefs: { line: number; prop: string }[] = [];
    visitWithScope(cached!.program, {
      onMember(prop, loc) {
        memberRefs.push({ line: loc.line, prop });
      },
    });
    
    // Should find 'name' on line 7 and 'age' on line 8
    expect(memberRefs.find(r => r.prop === "name" && r.line === 7)).toBeDefined();
    expect(memberRefs.find(r => r.prop === "age" && r.line === 8)).toBeDefined();
  });

  test("finds references to variable in correct scope", () => {
    const source = `
let x = 1

fn foo()
  let x = 2
  print(x)

fn bar()
  print(x)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const refs: { line: number; scope: string }[] = [];
    visitWithScope(cached!.program, {
      onIdent(name, loc, scope) {
        if (name === "x") {
          refs.push({ line: loc.line, scope });
        }
      },
    });
    
    // Should find references in different scopes
    const fooRef = refs.find(r => r.scope === "foo");
    expect(fooRef).toBeDefined();
    expect(fooRef!.line).toBe(6);
    
    const barRef = refs.find(r => r.scope === "bar");
    expect(barRef).toBeDefined();
    expect(barRef!.line).toBe(9);
  });

  test("finds method references on objects", () => {
    const source = `
type Counter
  value: number = 0

  fn increment()
    value = value + 1

  fn get(): number
    return value

let c = Counter()
c.increment()
c.increment()
print(c.get())
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    const memberRefs: { line: number; prop: string }[] = [];
    visitWithScope(cached!.program, {
      onMember(prop, loc) {
        memberRefs.push({ line: loc.line, prop });
      },
    });
    
    // Should find 'increment' on lines 12 and 13
    const incrementRefs = memberRefs.filter(r => r.prop === "increment");
    expect(incrementRefs.length).toBe(2);
    
    // Should find 'get' on line 14
    const getRefs = memberRefs.filter(r => r.prop === "get");
    expect(getRefs.length).toBe(1);
  });

  test("scopes member references by type - same member name in different types", () => {
    const source = `
type Person
  name: string
  age: number

type Animal
  name: string
  species: string

let p = Person(name: "John", age: 30)
let a = Animal(name: "Rex", species: "Dog")
print(p.name)
print(a.name)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // Find all member expressions and their object types
    const memberExprs: { prop: string; typeName: string | null; line: number }[] = [];
    visit(cached!.program, {
      expr(e) {
        if (e.kind === "MemberExpr") {
          const objType = e.object.resolvedType;
          let typeName: string | null = null;
          if (objType) {
            if (objType.kind === "object") typeName = (objType as any).name;
            else if (objType.kind === "ref") typeName = (objType as any).name;
          }
          memberExprs.push({ prop: e.property, typeName, line: e.loc.line });
        }
      },
    });
    
    // p.name should be on Person
    const pNameRef = memberExprs.find(e => e.line === 12 && e.prop === "name");
    expect(pNameRef).toBeDefined();
    expect(pNameRef!.typeName).toBe("Person");
    
    // a.name should be on Animal
    const aNameRef = memberExprs.find(e => e.line === 13 && e.prop === "name");
    expect(aNameRef).toBeDefined();
    expect(aNameRef!.typeName).toBe("Animal");
  });
});

describe("VSCode Extension - Member Access Type Resolution", () => {
  test("resolves object type from type map", () => {
    const source = `
type Person
  name: string
  age: number

let p = Person(name: "John", age: 30)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // Find the let statement
    const letStmt = cached!.program.body.find(s => s.kind === "LetStmt") as any;
    expect(letStmt).toBeDefined();
    
    // Get the type of the value (Person constructor call)
    const valueType = letStmt.value.resolvedType;
    expect(valueType).toBeDefined();
    expect(valueType!.kind).toBe("object");
    expect((valueType as any).name).toBe("Person");
  });

  test("finds MemberExpr in AST", () => {
    const source = `
type Person
  name: string

let p = Person(name: "John")
let n = p.name
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // Find member expressions
    const memberExprs: any[] = [];
    visit(cached!.program, {
      expr(e) {
        if (e.kind === "MemberExpr") {
          memberExprs.push(e);
        }
      },
    });
    
    // Should find p.name
    expect(memberExprs.length).toBeGreaterThanOrEqual(1);
    const pNameExpr = memberExprs.find(e => e.property === "name");
    expect(pNameExpr).toBeDefined();
    expect(pNameExpr.object.kind).toBe("Identifier");
    expect(pNameExpr.object.name).toBe("p");
  });

  test("resolves type through optional chain", () => {
    const source = `
type Person
  name: string

fn getName(p: Person?): string?
  return p?.name
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // Should parse without errors and handle optional member access
    const fn = cached!.program.body.find(s => s.kind === "FnDecl") as any;
    expect(fn).toBeDefined();
  });

  test("resolves generic type for member lookup", () => {
    const source = `
type Container[T]
  value: T
  count: number = 0

  fn get(): T
    return value

let c = Container[string]("hello")
print(c.value)
print(c.count)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // Find 'c' variable's type
    const letStmt = cached!.program.body.find(s => s.kind === "LetStmt") as any;
    expect(letStmt).toBeDefined();
    
    const valueType = letStmt.value.resolvedType;
    expect(valueType).toBeDefined();
    
    // Type should be defined - could be generic, object, ref, or any depending on type checker
    // The important thing is that getTypeNameForMemberLookup can extract a name
    const kind = valueType!.kind;
    expect(kind).toBeDefined();
  });

  test("distinguishes members between different types with same name", () => {
    const source = `
type Person
  name: string
  age: number

  fn greet(): string
    return "Hello from Person"

type Animal
  name: string
  species: string

  fn greet(): string
    return "Hello from Animal"

let p = Person(name: "John", age: 30)
let a = Animal(name: "Rex", species: "Dog")
print(p.name)
print(a.name)
print(p.greet())
print(a.greet())
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // Find Person.name field
    const personType = cached!.program.body.find(
      s => s.kind === "TypeDecl" && (s as any).name === "Person"
    ) as any;
    expect(personType).toBeDefined();
    const personNameField = personType.body.members.find((m: any) => m.name === "name" && m.kind === "FieldDecl");
    expect(personNameField).toBeDefined();
    expect(personNameField.loc.line).toBe(3);
    
    // Find Animal.name field
    const animalType = cached!.program.body.find(
      s => s.kind === "TypeDecl" && (s as any).name === "Animal"
    ) as any;
    expect(animalType).toBeDefined();
    const animalNameField = animalType.body.members.find((m: any) => m.name === "name" && m.kind === "FieldDecl");
    expect(animalNameField).toBeDefined();
    expect(animalNameField.loc.line).toBe(10);
    
    // These are different locations - go-to-definition should navigate to the correct one
    expect(personNameField.loc.line).not.toBe(animalNameField.loc.line);
  });

  test("finds correct type from member expression object", () => {
    const source = `
type First
  value: number = 1

type Second
  value: number = 2

let f = First()
let s = Second()
print(f.value)
print(s.value)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();
    
    // Find member expressions
    const memberExprs: any[] = [];
    visit(cached!.program, {
      expr(e) {
        if (e.kind === "MemberExpr" && e.property === "value") {
          memberExprs.push(e);
        }
      },
    });
    
    // Should find two .value member accesses
    expect(memberExprs.length).toBe(2);
    
    // Check the object types are correctly resolved
    for (const expr of memberExprs) {
      const objType = expr.object.resolvedType;
      expect(objType).toBeDefined();
      // Type should be resolvable
      expect(["object", "ref"]).toContain(objType!.kind);
    }
  });
});

// ============================================
// LSP Module Tests - Symbol Resolution
// ============================================

describe("LSP Module - Symbol Resolution", () => {
  test("resolveDefinition finds correct field with same name in different types", () => {
    const source = `
type Person
  name: string
  age: number

type Animal
  name: string
  species: string

let p = Person(name: "John", age: 30)
let a = Animal(name: "Rex", species: "Dog")
print(p.name)
print(a.name)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Line 12 (1-indexed): print(p.name) - the "name" is at column ~9
    // We want to test that go-to-definition on p.name goes to Person.name (line 3)
    const personNameDef = resolveDefinition(cached!.symbols, 12, 9);
    expect(personNameDef).toBeDefined();
    expect(personNameDef!.name).toBe("name");
    expect(personNameDef!.id.qualifiedName).toBe("Person.name");
    expect(personNameDef!.loc.line).toBe(3);

    // Line 13 (1-indexed): print(a.name) - the "name" is at column ~9
    // We want to test that go-to-definition on a.name goes to Animal.name (line 7)
    const animalNameDef = resolveDefinition(cached!.symbols, 13, 9);
    expect(animalNameDef).toBeDefined();
    expect(animalNameDef!.name).toBe("name");
    expect(animalNameDef!.id.qualifiedName).toBe("Animal.name");
    expect(animalNameDef!.loc.line).toBe(7);
  });

  test("resolveDefinition finds correct method with same name in different types", () => {
    const source = `
type Dog
  fn speak(): string
    return "Woof"

type Cat
  fn speak(): string
    return "Meow"

let d = Dog()
let c = Cat()
print(d.speak())
print(c.speak())
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Line 12: print(d.speak()) - "speak" starts around column 9
    const dogSpeakDef = resolveDefinition(cached!.symbols, 12, 9);
    expect(dogSpeakDef).toBeDefined();
    expect(dogSpeakDef!.name).toBe("speak");
    expect(dogSpeakDef!.id.qualifiedName).toBe("Dog.speak");
    expect(dogSpeakDef!.loc.line).toBe(3);

    // Line 13: print(c.speak()) - "speak" starts around column 9
    const catSpeakDef = resolveDefinition(cached!.symbols, 13, 9);
    expect(catSpeakDef).toBeDefined();
    expect(catSpeakDef!.name).toBe("speak");
    expect(catSpeakDef!.id.qualifiedName).toBe("Cat.speak");
    expect(catSpeakDef!.loc.line).toBe(7);
  });

  test("resolveDefinition works for generic type members", () => {
    const source = `
type Container[T]
  value: T
  count: number = 0

  fn get(): T
    return value

let box = Container[string]("hello")
print(box.value)
print(box.count)
print(box.get())
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Line 10: print(box.value) - "value" is around column 11
    const valueDef = resolveDefinition(cached!.symbols, 10, 11);
    expect(valueDef).toBeDefined();
    expect(valueDef!.name).toBe("value");
    expect(valueDef!.id.qualifiedName).toBe("Container.value");
    expect(valueDef!.loc.line).toBe(3);

    // Line 11: print(box.count) - "count" is around column 11
    const countDef = resolveDefinition(cached!.symbols, 11, 11);
    expect(countDef).toBeDefined();
    expect(countDef!.name).toBe("count");
    expect(countDef!.id.qualifiedName).toBe("Container.count");

    // Line 12: print(box.get()) - "get" is around column 11
    const getDef = resolveDefinition(cached!.symbols, 12, 11);
    expect(getDef).toBeDefined();
    expect(getDef!.name).toBe("get");
    expect(getDef!.id.qualifiedName).toBe("Container.get");
    expect(getDef!.loc.line).toBe(6);
  });

  test("resolveDefinition works for nested member chains", () => {
    const source = `
type Person
  name: string
  age: number

  fn greet(): string
    "Hello, " + name

type Wrapper
  inner: Person = Person("John", 20)

  fn get_person(): Person
    return inner

let w = Wrapper()
print(w.inner.name)
print(w.inner.greet())
print(w.get_person().name)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Line 16: print(w.inner.name) - "name" is around column 15
    const nameDef = resolveDefinition(cached!.symbols, 16, 15);
    expect(nameDef).toBeDefined();
    expect(nameDef!.name).toBe("name");
    expect(nameDef!.id.qualifiedName).toBe("Person.name");

    // Line 17: print(w.inner.greet()) - "greet" is around column 15
    const greetDef = resolveDefinition(cached!.symbols, 17, 15);
    expect(greetDef).toBeDefined();
    expect(greetDef!.name).toBe("greet");
    expect(greetDef!.id.qualifiedName).toBe("Person.greet");

    // Line 18: print(w.get_person().name) - "name" is around column 22
    const nameDef2 = resolveDefinition(cached!.symbols, 18, 22);
    expect(nameDef2).toBeDefined();
    expect(nameDef2!.name).toBe("name");
    expect(nameDef2!.id.qualifiedName).toBe("Person.name");
  });

  test("findReferences finds field usage inside method bodies", () => {
    const source = `
type Hello
  name: string
  age: number

  fn greet(): string
    "Hello, {name}"

  fn info(): string
    name + " is " + str(age) + " years old"
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Find references from the "name" field definition (line 3)
    const nameRefs = findReferences(cached!.symbols, 3, 3);
    expect(nameRefs).toBeDefined();
    expect(nameRefs!.definition.id.qualifiedName).toBe("Hello.name");
    // Should find 2 references: one in greet() template, one in info()
    expect(nameRefs!.references.length).toBe(2);

    // Find references from the "age" field definition (line 4)
    const ageRefs = findReferences(cached!.symbols, 4, 3);
    expect(ageRefs).toBeDefined();
    expect(ageRefs!.definition.id.qualifiedName).toBe("Hello.age");
    // Should find 1 reference in info()
    expect(ageRefs!.references.length).toBe(1);
  });

  test("scope walking resolves parameters before type fields", () => {
    const source = `
type Person
  name: string

  fn greet(name: string): string
    "Hello, " + name
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Line 6: "Hello, " + name - "name" should resolve to the parameter, not the field
    // The parameter is at Person.greet.name
    const refs = cached!.symbols.references;
    const nameRef = refs.find(r => r.loc.line === 6);
    expect(nameRef).toBeDefined();
    expect(nameRef!.symbolId.qualifiedName).toBe("Person.greet.name");
  });

  test("scope walking falls back to type fields when no parameter matches", () => {
    const source = `
type Person
  name: string
  age: number

  fn greet(person: string): string
    "Hello, " + person + " from " + name
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Check that both parameter and field are correctly resolved
    const refs = cached!.symbols.references;
    const personRef = refs.find(r => r.symbolId.qualifiedName === "Person.greet.person");
    const nameRef = refs.find(r => r.symbolId.qualifiedName === "Person.name");
    
    expect(personRef).toBeDefined();
    expect(nameRef).toBeDefined();
  });

  test("template string identifiers have correct locations", () => {
    const source = `
type Hello
  name: string

  fn greet(): string
    "Hello, {name}"
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // The identifier "name" inside the template should have the correct column
    // Line 6: "Hello, {name}"  - "name" starts after the opening quote and "Hello, {"
    const refs = cached!.symbols.references;
    const nameRef = refs.find(r => r.loc.line === 6);
    expect(nameRef).toBeDefined();
    // Column should be around 14 (5 for indent + 1 for quote + 8 for "Hello, {")
    expect(nameRef!.loc.column).toBeGreaterThan(10);
  });

  test("resolveDefinition works on template string identifiers", () => {
    const source = `
type Hello
  name: string

  fn greet(): string
    "Hello, {name}"
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Get the location of the name reference in the template
    const refs = cached!.symbols.references;
    const nameRef = refs.find(r => r.loc.line === 6);
    expect(nameRef).toBeDefined();

    // Now resolve at that location
    const def = resolveDefinition(cached!.symbols, nameRef!.loc.line, nameRef!.loc.column);
    expect(def).toBeDefined();
    expect(def!.name).toBe("name");
    expect(def!.id.qualifiedName).toBe("Hello.name");
  });

  test("multiple template expressions have correct locations", () => {
    const source = `
type Greeter
  name: string

  fn greet(person: string): string
    "Hello, {person} from {name}"
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    const refs = cached!.symbols.references.filter(r => r.loc.line === 6);
    expect(refs.length).toBe(2);

    // First should be person (parameter), second should be name (field)
    const personRef = refs.find(r => r.symbolId.qualifiedName === "Greeter.greet.person");
    const nameRef = refs.find(r => r.symbolId.qualifiedName === "Greeter.name");
    
    expect(personRef).toBeDefined();
    expect(nameRef).toBeDefined();
    
    // person comes before name in the string, so its column should be smaller
    expect(personRef!.loc.column).toBeLessThan(nameRef!.loc.column);
  });

  test("findReferences scopes by type for same-named fields", () => {
    const source = `
type A
  value: number = 1

type B
  value: number = 2

let a = A()
let b = B()
print(a.value)
print(b.value)
print(a.value + b.value)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Find references from A.value definition (line 3)
    const aRefs = findReferences(cached!.symbols, 3, 3);
    expect(aRefs).toBeDefined();
    expect(aRefs!.definition.id.qualifiedName).toBe("A.value");
    // Should have references from a.value usages only
    const aRefLines = aRefs!.references.map(r => r.loc.line);
    expect(aRefLines).toContain(10); // print(a.value)
    expect(aRefLines).toContain(12); // print(a.value + b.value)
    expect(aRefLines).not.toContain(11); // NOT b.value

    // Find references from B.value definition (line 6)
    const bRefs = findReferences(cached!.symbols, 6, 3);
    expect(bRefs).toBeDefined();
    expect(bRefs!.definition.id.qualifiedName).toBe("B.value");
    // Should have references from b.value usages only
    const bRefLines = bRefs!.references.map(r => r.loc.line);
    expect(bRefLines).toContain(11); // print(b.value)
    expect(bRefLines).toContain(12); // print(a.value + b.value)
    expect(bRefLines).not.toContain(10); // NOT a.value
  });

  test("resolveDefinition works for function calls", () => {
    const source = `
fn greet(name: string): string
  return "Hello, " + name

fn main()
  print(greet("World"))
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Line 6: print(greet("World")) - "greet" is around column 9
    const greetDef = resolveDefinition(cached!.symbols, 6, 9);
    expect(greetDef).toBeDefined();
    expect(greetDef!.name).toBe("greet");
    expect(greetDef!.id.kind).toBe("function");
    expect(greetDef!.loc.line).toBe(2);
  });

  test("resolveDefinition works for variable references", () => {
    const source = `
fn compute()
  let x = 10
  let y = x + 5
  return y
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Line 4: let y = x + 5 - "x" is around column 11
    const xDef = resolveDefinition(cached!.symbols, 4, 11);
    expect(xDef).toBeDefined();
    expect(xDef!.name).toBe("x");
    expect(xDef!.id.kind).toBe("variable");
    expect(xDef!.loc.line).toBe(3);
  });

  test("getRenameLocations returns all locations for variable rename", () => {
    const source = `
fn compute()
  let x = 10
  let y = x + 5
  return x * y
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Get rename locations for "x" (definition at line 3)
    const locations = getRenameLocations(cached!.symbols, 3, 7);
    expect(locations).toBeDefined();
    expect(locations!.length).toBeGreaterThanOrEqual(3); // definition + 2 usages
    
    const lines = locations!.map(l => l.loc.line);
    expect(lines).toContain(3); // let x = 10
    expect(lines).toContain(4); // x + 5
    expect(lines).toContain(5); // x * y
  });

  test("getRenameLocations returns all locations for function rename", () => {
    const source = `
fn greet(name: string): string
  return "Hello, " + name

fn main()
  print(greet("World"))
  print(greet("Test"))
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Get rename locations for "greet" (definition at line 2)
    const locations = getRenameLocations(cached!.symbols, 2, 4);
    expect(locations).toBeDefined();
    expect(locations!.length).toBeGreaterThanOrEqual(3); // definition + 2 calls
    
    const lines = locations!.map(l => l.loc.line);
    expect(lines).toContain(2); // fn greet
    expect(lines).toContain(6); // greet("World")
    expect(lines).toContain(7); // greet("Test")
  });

  test("getRenameLocations scopes by type for field rename", () => {
    const source = `
type A
  value: number = 1

type B
  value: number = 2

let a = A()
let b = B()
print(a.value)
print(b.value)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Get rename locations for A.value (line 3)
    const aLocations = getRenameLocations(cached!.symbols, 3, 3);
    expect(aLocations).toBeDefined();
    
    // Should include definition and a.value reference, but NOT b.value
    const aLines = aLocations!.map(l => l.loc.line);
    expect(aLines).toContain(3);  // A.value definition
    expect(aLines).toContain(10); // a.value usage
    expect(aLines).not.toContain(6);  // NOT B.value definition
    expect(aLines).not.toContain(11); // NOT b.value usage

    // Get rename locations for B.value (line 6)
    const bLocations = getRenameLocations(cached!.symbols, 6, 3);
    expect(bLocations).toBeDefined();
    
    const bLines = bLocations!.map(l => l.loc.line);
    expect(bLines).toContain(6);  // B.value definition
    expect(bLines).toContain(11); // b.value usage
    expect(bLines).not.toContain(3);  // NOT A.value definition
    expect(bLines).not.toContain(10); // NOT a.value usage
  });
});

describe("LSP Module - Hover Info", () => {
  test("getHoverForSymbol returns function signature", () => {
    const source = `
fn greet(name: string): string
  return "Hello, " + name
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Hover on "greet" at line 2, column 4
    const hover = getHoverForSymbol(cached!.symbols, cached!.program, 2, 4, cached!.env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("fn greet");
    expect(hover!.signature).toContain("name: string");
    expect(hover!.signature).toContain(": string");
  });

  test("getHoverForSymbol returns type signature", () => {
    const source = `
type Person
  name: string
  age: number
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Hover on "Person" at line 2, column 6
    const hover = getHoverForSymbol(cached!.symbols, cached!.program, 2, 6, cached!.env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("type Person");
    expect(hover!.doc).toContain("name: string");
    expect(hover!.doc).toContain("age: number");
  });

  test("getHoverForSymbol returns field info", () => {
    const source = `
type Person
  name: string
  age: number
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Hover on "name" field at line 3, column 3
    const hover = getHoverForSymbol(cached!.symbols, cached!.program, 3, 3, cached!.env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toBe("(field) name: string");
  });

  test("getHoverForSymbol returns method info", () => {
    const source = `
type Calculator
  fn add(a: number, b: number): number
    return a + b
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Hover on "add" method at line 3, column 6
    const hover = getHoverForSymbol(cached!.symbols, cached!.program, 3, 6, cached!.env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("(method) fn add");
    expect(hover!.signature).toContain("a: number");
    expect(hover!.signature).toContain("b: number");
  });

  test("getHoverForSymbol returns variable info", () => {
    const source = `
fn main()
  let x = 42
  print(x)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Hover on "x" definition at line 3, column 7
    const hover = getHoverForSymbol(cached!.symbols, cached!.program, 3, 7, cached!.env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toContain("x");
    expect(hover!.signature).toContain("number");
  });

  test("getHoverForSymbol returns parameter info", () => {
    const source = `
fn greet(name: string): string
  return "Hello, " + name
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Hover on "name" parameter at line 2, column 10
    const hover = getHoverForSymbol(cached!.symbols, cached!.program, 2, 10, cached!.env);
    expect(hover).not.toBeNull();
    expect(hover!.signature).toBe("(parameter) name: string");
  });
});

describe("LSP Module - Document Symbols", () => {
  test("getDocumentSymbols returns functions and types", () => {
    const source = `
fn greet(name: string): string
  return "Hello, " + name

fn farewell(): string
  return "Goodbye"

type Person
  name: string
  age: number

type Animal
  species: string
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    const symbols = getDocumentSymbols(cached!.symbols);
    
    // Should have 2 functions and 2 types
    const functions = symbols.filter(s => s.kind === "function");
    const types = symbols.filter(s => s.kind === "type");
    expect(functions.length).toBe(2);
    expect(types.length).toBe(2);
    
    expect(functions.map(f => f.name)).toContain("greet");
    expect(functions.map(f => f.name)).toContain("farewell");
    expect(types.map(t => t.name)).toContain("Person");
    expect(types.map(t => t.name)).toContain("Animal");
  });

  test("getDocumentSymbols includes type members", () => {
    const source = `
type Calculator
  value: number = 0

  fn add(n: number): number
    return value + n

  fn subtract(n: number): number
    return value - n
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    const symbols = getDocumentSymbols(cached!.symbols);
    
    // Should have 1 type, 1 field, 2 methods (add + subtract)
    const types = symbols.filter(s => s.kind === "type");
    const fields = symbols.filter(s => s.kind === "field");
    const methods = symbols.filter(s => s.kind === "method");
    
    expect(types.length).toBe(1);
    expect(types[0].name).toBe("Calculator");
    
    expect(fields.length).toBe(1);
    expect(fields[0].name).toBe("value");
    expect(fields[0].parent).toBe("Calculator");
    
    expect(methods.length).toBe(2);
    expect(methods.map(m => m.name)).toContain("add");
    expect(methods.map(m => m.name)).toContain("subtract");
    expect(methods[0].parent).toBe("Calculator");
  });

  test("getDocumentSymbols excludes local variables and parameters", () => {
    const source = `
fn compute(a: number, b: number): number
  let x = a + b
  let y = x * 2
  return y

type Person
  name: string
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    const symbols = getDocumentSymbols(cached!.symbols);
    
    // Should NOT include parameters (a, b) or local variables (x, y)
    const names = symbols.map(s => s.name);
    expect(names).toContain("compute");
    expect(names).toContain("Person");
    expect(names).toContain("name"); // field
    
    expect(names).not.toContain("a"); // parameter
    expect(names).not.toContain("b"); // parameter
    expect(names).not.toContain("x"); // local variable
    expect(names).not.toContain("y"); // local variable
  });
});

describe("LSP Module - Completions", () => {
  test("resolveObjectType resolves ref types", () => {
    const source = `
type Person
  name: string
  age: number

let p = Person(name: "John", age: 30)
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // The type of 'p' should be resolvable to Person
    const letStmt = cached!.program.body.find(s => s.kind === "LetStmt") as any;
    expect(letStmt).toBeDefined();
    
    const valueType = letStmt.value.resolvedType;
    expect(valueType).toBeDefined();
    
    const resolved = resolveObjectType(cached!.program, valueType!, cached!.env);
    expect(resolved).not.toBeNull();
    expect(resolved!.name).toBe("Person");
  });

  test("resolveObjectType resolves ref type to object with members", () => {
    const source = `
type Calculator
  value: number = 0

  fn add(n: number): number
    return value + n

  fn reset()
    value = 0
`;
    const cached = parseDocument(source);
    expect(cached).not.toBeNull();

    // Try to resolve via ref type
    const refType = { kind: "ref", name: "Calculator" } as any;
    const obj = resolveObjectType(cached!.program, refType, cached!.env);
    expect(obj).not.toBeNull();
    expect(obj!.name).toBe("Calculator");
    
    // Check properties
    expect(obj!.properties.length).toBe(1);
    expect(obj!.properties[0].name).toBe("value");
    
    // Check methods
    expect(obj!.methods.length).toBe(2);
    const methodNames = obj!.methods.map(m => m.name);
    expect(methodNames).toContain("add");
    expect(methodNames).toContain("reset");
  });
});
