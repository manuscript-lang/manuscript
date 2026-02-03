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
      extends: [{ kind: "NamedType", name: "string" }],
    });
  });

  test("function type alias", () => {
    const src = "type Handler = fn(Request): Response";
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Handler",
      extends: [{
        kind: "FunctionType",
        params: [{ kind: "NamedType", name: "Request" }],
        returnType: { kind: "NamedType", name: "Response" },
      }],
    });
  });

  test("union type alias", () => {
    const src = "type Message = Text or Image or File";
    const result = program(src);
    // Union is parsed as a single UnionType in extends
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Message",
    });
    // Check that extends contains a union type
    const typeDecl = result.body[0] as any;
    expect(typeDecl.extends[0]).toMatchObject({
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

  test("type extends", () => {
    const src = `type Admin extends User
  permissions: list[string]`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      name: "Admin",
      extends: [{ kind: "NamedType", name: "User" }],
    });
  });

  test("multiple inheritance", () => {
    const src = `type Duck extends Animal, Flyable, Swimmable
  name: string`;
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "TypeDecl",
      extends: [
        { kind: "NamedType", name: "Animal" },
        { kind: "NamedType", name: "Flyable" },
        { kind: "NamedType", name: "Swimmable" },
      ],
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
  test("simple keyword", () => {
    const src = "keyword capabilities = type extends Context";
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "KeywordDecl",
      name: "capabilities",
      expansion: "type",
      extends: { kind: "NamedType", name: "Context" },
    });
  });

  test("keyword with using", () => {
    const src = "keyword agent = type extends Agent using (LLM)";
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
      sealed: "sealed",
      name: "enum",
    });
  });

  test("sealed(using) keyword", () => {
    const src = "sealed(using) keyword model = type";
    const result = program(src);
    expect(result.body[0]).toMatchObject({
      kind: "KeywordDecl",
      sealed: "sealed(using)",
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
