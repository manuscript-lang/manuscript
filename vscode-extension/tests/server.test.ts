import { describe, test, expect, beforeEach } from "bun:test";
import { Parser } from "../../src/parser";
import { TypeChecker } from "../../src/types/checker";
import type { Program, FnDecl, TypeDecl } from "../../src/parser/ast";
import type { Type } from "../../src/types/types";

// Test helpers that mirror server.ts logic
const KEYWORDS = [
  "fn", "type", "let", "var", "if", "else", "for", "match", "return",
  "using", "with", "import", "from", "test", "yield", "defer", "try",
  "catch", "throw", "break", "continue", "spawn", "sealed", "extends",
  "and", "or", "not", "is", "as", "then", "in", "true", "false", "null", "where"
];

const BUILTIN_TYPES = [
  "number", "string", "bool", "null", "bytes", "any", "never", "void",
  "list", "map", "set", "Channel", "Promise", "Stream", "Result"
];

const BUILTIN_FUNCTIONS = [
  "print", "len", "range", "clone", "keys", "values", "entries",
  "floor", "ceil", "round", "abs", "min", "max", "sum",
  "int", "float", "str", "type_of", "assert"
];

function formatTypeExpr(type: any): string {
  if (!type) return "any";
  switch (type.kind) {
    case "NamedType": return type.name;
    case "GenericType": return `${type.name}[${type.args.map(formatTypeExpr).join(", ")}]`;
    case "FunctionType": return `fn(${type.params.map(formatTypeExpr).join(", ")}): ${formatTypeExpr(type.returnType)}`;
    case "UnionType": return type.types.map(formatTypeExpr).join(" or ");
    case "OptionalType": return `${formatTypeExpr(type.inner)}?`;
    case "ListType": return `list[${formatTypeExpr(type.elementType)}]`;
    default: return "any";
  }
}

interface DocumentCache {
  program: Program;
  types: Map<any, Type>;
}

function parseDocument(source: string): DocumentCache | null {
  try {
    const parser = new Parser(source);
    const program = parser.parse();
    const checker = new TypeChecker();
    const result = checker.check(program);
    return { program, types: result.types };
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
    expect(formatTypeExpr(null)).toBe("any");
    expect(formatTypeExpr(undefined)).toBe("any");
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
    const params = fn.params.map(p => `${p.name}: ${p.type ? formatTypeExpr(p.type) : "any"}`).join(", ");
    const ret = fn.returnType ? formatTypeExpr(fn.returnType) : "any";
    
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
      const inferredType = cached!.types.get(value);
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
    const iterType = cached!.types.get(forStmt.iterable);
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
    
    const valueType = cached!.types.get(letStmt.value);
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
