import { describe, test, expect } from "bun:test";
import { program, stmt, expectParseError } from "../helpers";

describe("Parser - Import Declarations", () => {
  test("simple import", () => {
    const src = 'import { Coder } from "agents/coder"';
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "ImportDecl",
      names: [{ name: "Coder" }],
      source: "agents/coder",
    });
  });

  test("import with alias", () => {
    const src = 'import { Claude as LLM } from "anthropic"';
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "ImportDecl",
      names: [{ name: "Claude", alias: "LLM" }],
    });
  });

  test("multiple imports", () => {
    const src = 'import { a, b, c } from "lib"';
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "ImportDecl",
      names: [{ name: "a" }, { name: "b" }, { name: "c" }],
    });
  });
});

describe("Parser - Function Declarations", () => {
  test("simple function", () => {
    const src = `fn add(a, b)
  a + b`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "FnDecl",
      name: "add",
      params: [
        { kind: "Parameter", name: "a" },
        { kind: "Parameter", name: "b" },
      ],
    });
  });

  test("function with types", () => {
    const src = `fn add(a: number, b: number): number
  a + b`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "FnDecl",
      name: "add",
      params: [
        { name: "a", type: { kind: "NamedType", name: "number" } },
        { name: "b", type: { kind: "NamedType", name: "number" } },
      ],
      returnType: { kind: "NamedType", name: "number" },
    });
  });

  test("function with optional param", () => {
    const src = `fn greet(name: string, greeting?: string)
  greeting ?? "Hello"`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "FnDecl",
      params: [
        { name: "name", optional: false },
        { name: "greeting", optional: true },
      ],
    });
  });

  test("function with default param", () => {
    const src = `fn greet(name: string, greeting: string = "Hello")
  greeting`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "FnDecl",
      params: [
        { name: "name" },
        { name: "greeting", optional: true, defaultValue: { kind: "Literal", value: "Hello" } },
      ],
    });
  });

  test("variadic function", () => {
    const src = `fn log(level: string, ...messages: list[string])
  print(messages)`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "FnDecl",
      params: [
        { name: "level", rest: false },
        { name: "messages", rest: true },
      ],
    });
  });

  test("function with using", () => {
    const src = `fn read_file(path: string) using (fs: Filesystem)
  fs.read(path)`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "FnDecl",
      using: {
        kind: "UsingClause",
        bindings: [{ kind: "ContextBinding", name: "fs", type: { kind: "NamedType", name: "Filesystem" } }],
      },
    });
  });

  test("function with pass-through using", () => {
    const src = `fn process(task: string) using (Filesystem)
  read("config.txt")`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "FnDecl",
      using: {
        bindings: [{ kind: "ContextBinding", type: { kind: "NamedType", name: "Filesystem" } }],
      },
    });
  });

  test("generator function detected", () => {
    const src = `fn seq()
  yield 1
  yield 2`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "FnDecl",
      isGenerator: true,
    });
  });
});

describe("Parser - Type Declarations", () => {
  test("type alias", () => {
    const src = "type UserID = string";
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "UserID",
      alias: [{ kind: "NamedType", name: "string" }],
    });
  });

  test("function type alias", () => {
    const src = "type Handler = fn(Request): Response";
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Handler",
      alias: [{
        kind: "FunctionType",
        params: [{ kind: "NamedType", name: "Request" }],
        returnType: { kind: "NamedType", name: "Response" },
      }],
    });
  });

  test("union type alias", () => {
    const src = "type Message = Text or Image or File";
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Message",
    });
    const typeDecl = result.body[0] as any;
    expect(typeDecl.alias[0]).toMatchObject({
      kind: "UnionType",
      types: [
        { kind: "NamedType", name: "Text" },
        { kind: "NamedType", name: "Image" },
        { kind: "NamedType", name: "File" },
      ],
    });
  });

  test("literal union type", () => {
    const src = 'type Status = "pending" or "done"';
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Status",
    });
  });

  test("context type declaration", () => {
    const src = `context Filesystem
  fn read(path: string): string`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Filesystem",
      isContextType: true,
    });
    const decl = result.body[0] as any;
    expect(decl.body.members).toHaveLength(1);
    expect(decl.body.members[0]).toMatchObject({ kind: "MethodDecl", name: "read" });
  });

  test("context type with no body", () => {
    const src = "context Empty";
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Empty",
      isContextType: true,
      body: { kind: "TypeBody", members: [] },
    });
  });

  test("struct type", () => {
    const src = `type User
  id: number
  name: string`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "User",
      body: {
        kind: "TypeBody",
        members: [
          { kind: "FieldDecl", name: "id" },
          { kind: "FieldDecl", name: "name" },
        ],
      },
    });
  });

  test("type with optional field", () => {
    const src = `type User
  email?: string`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      body: {
        members: [{ kind: "FieldDecl", name: "email", optional: true }],
      },
    });
  });

  test("type with default value", () => {
    const src = `type User
  role: string = "user"`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      body: {
        members: [{
          kind: "FieldDecl",
          name: "role",
          defaultValue: { kind: "Literal", value: "user" },
        }],
      },
    });
  });

  test("type with computed field", () => {
    const src = `type User
  display: () => "{name}"`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      body: {
        members: [{ kind: "FieldDecl", name: "display", computed: true }],
      },
    });
  });

  test("type with methods", () => {
    const src = `type Counter
  value: number = 0
  fn increment()
    value = value + 1`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      body: {
        members: [
          { kind: "FieldDecl", name: "value" },
          { kind: "MethodDecl", name: "increment" },
        ],
      },
    });
  });

  test("type with embedding", () => {
    const src = `type Admin
  User
  permissions: list[string]`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Admin",
      body: {
        members: [
          { kind: "FieldDecl", name: "User", embedded: true },
          { kind: "FieldDecl", name: "permissions" },
        ],
      },
    });
  });

  test("generic type", () => {
    const src = `type Box[T]
  value: T`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Box",
      typeParams: [{ kind: "TypeParam", name: "T" }],
    });
  });

  test("generic with constraint", () => {
    const src = `type Container[T] where T: Comparable
  items: list[T]`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      where: [{ param: "T", constraint: { kind: "NamedType", name: "Comparable" } }],
    });
  });
});

describe("Parser - Keyword Declarations", () => {
  test("simple type keyword", () => {
    const src = "keyword capabilities = type";
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "KeywordDecl",
      name: "capabilities",
      expansion: "type",
    });
  });

  test("keyword with using", () => {
    const src = "keyword agent = type using (LLM)";
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "KeywordDecl",
      name: "agent",
      using: { bindings: [{ kind: "ContextBinding", type: { name: "LLM" } }] },
    });
  });

  test("function keyword", () => {
    const src = "keyword prompt = fn: string";
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "KeywordDecl",
      name: "prompt",
      expansion: "fn",
      returnType: { kind: "NamedType", name: "string" },
    });
  });

  test("sealed keyword", () => {
    const src = "sealed keyword enum = type";
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "KeywordDecl",
      sealed: true,
      name: "enum",
    });
  });
});

describe("Parser - Test Declarations", () => {
  test("simple test", () => {
    const src = `test "description"
  assert true`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TestDecl",
      description: "description",
    });
  });

  test("test with capabilities", () => {
    const src = `test "with mocks" with testing()
  let result = run()`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TestDecl",
      withClause: { kind: "CallExpr" },
    });
  });
});

describe("Parser - Full Programs", () => {
  test("multiple declarations", () => {
    const src = `type User
  name: string

fn greet(user: User): string
  "Hello, " + user.name

test "greet works"
  let u = User(name: "Alice")
  assert greet(u) == "Hello, Alice"`;
    
    const result = program(src);
    expect(result.body).toHaveLength(3);
    expect(result.body[0]?.kind).toBe("TypeDecl");
    expect(result.body[1]?.kind).toBe("FnDecl");
    expect(result.body[2]?.kind).toBe("TestDecl");
  });

  test("program with imports", () => {
    const src = `import { Claude } from "anthropic"

fn main()
  print("hello")`;
    
    const result = program(src);
    expect(result.body[0]?.kind).toBe("ImportDecl");
    expect(result.body[1]?.kind).toBe("FnDecl");
  });
});

describe("Parser - Documentation Comments", () => {
  test("function with doc comment", () => {
    const src = `// Adds two numbers
fn add(a: number, b: number): number
  a + b`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "FnDecl",
      name: "add",
      doc: "Adds two numbers",
    });
  });

  test("function with multi-line doc comment", () => {
    const src = `// Adds two numbers together
// Returns the sum
fn add(a: number, b: number): number
  a + b`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "FnDecl",
      name: "add",
      doc: "Adds two numbers together\nReturns the sum",
    });
  });

  test("extern function with doc comment", () => {
    const src = `// Prints values to console
extern fn print(...args: any): void`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "ExternFnDecl",
      name: "print",
      doc: "Prints values to console",
    });
  });

  test("type with doc comment", () => {
    const src = `// A 2D point
type Point
  x: number
  y: number`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Point",
      doc: "A 2D point",
    });
  });

  test("type fields with doc comments", () => {
    const src = `type Point
  // X coordinate
  x: number
  // Y coordinate  
  y: number`;
    const result = program(src);
    const typeDecl = result.body[0] as any;
    expect(typeDecl.body.members[0]).toMatchObject({
      kind: "FieldDecl",
      name: "x",
      doc: "X coordinate",
    });
    expect(typeDecl.body.members[1]).toMatchObject({
      kind: "FieldDecl",
      name: "y",
      doc: "Y coordinate",
    });
  });

  test("type methods with doc comments", () => {
    const src = `type Point
  x: number
  // Calculates distance from origin
  fn distance(): number
    self.x * 2`;
    const result = program(src);
    const typeDecl = result.body[0] as any;
    expect(typeDecl.body.members[1]).toMatchObject({
      kind: "MethodDecl",
      name: "distance",
      doc: "Calculates distance from origin",
    });
  });

  test("extern type with doc comment", () => {
    const src = `// HTTP response object
extern type Response`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Response",
      isExtern: true,
      doc: "HTTP response object",
    });
  });

  test("no doc when comment is not immediately before", () => {
    const src = `// Comment

fn add(a: number, b: number): number
  a + b`;
    const result = program(src);
    expect((result.body[0] as any).doc).toBeUndefined();
  });

  test("multiple declarations with separate docs", () => {
    const src = `// First function
fn foo(): number
  1

// Second function
fn bar(): number
  2`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "FnDecl",
      name: "foo",
      doc: "First function",
    });
    expect(result.body[1]).toMatchObject({
      kind: "FnDecl",
      name: "bar",
      doc: "Second function",
    });
  });
});
