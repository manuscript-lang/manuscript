import { describe, test, expect } from "bun:test";
import {
  findFnDecl,
  findTypeDecl,
  findConstructorCalleeAt,
  formatFnSignature,
  formatTypeSignature,
  getDocstring,
  resolveObjectType,
} from "../../src/lsp";
import {
  isLocationMatch,
  isDefLocationMatch,
  findTypeMember,
  formatAstType,
  formatMethodSignature,
  formatFunctionType,
  formatTypeSignatureFromObject,
  parseQualifiedName,
  parseMemberQualifiedName,
} from "../../src/lsp/utils";
import type { SymbolDef } from "../../src/lsp/symbols";
import { Parser } from "../../src/parser";
import { TypeChecker } from "../../src/types";

describe("LSP Utils", () => {
  test("isLocationMatch and isDefLocationMatch: position inside/outside name range", () => {
    expect(isLocationMatch({ line: 1, column: 5 }, 0, 3, 2, 1)).toBe(false);
    expect(isLocationMatch({ line: 1, column: 5 }, 0, 3, 1, 6)).toBe(true);
    expect(isLocationMatch({ line: 1, column: 5 }, 0, 3, 1, 4)).toBe(false);
    expect(isLocationMatch({ line: 1, column: 5 }, 0, 3, 1, 9)).toBe(false);
    const def: SymbolDef = { id: { kind: "function", qualifiedName: "foo" }, name: "foo", loc: { line: 1, column: 0 }, nameOffset: 0 };
    expect(isDefLocationMatch(def, 1, 1)).toBe(true);
    expect(isDefLocationMatch(def, 1, 4)).toBe(false);
  });

  test("findFnDecl, findTypeDecl, findTypeMember find decls or null", () => {
    const program = new Parser(`
fn bar(): number
  return 0
type Person
  name: string
  fn greet(): string
`).parse();
    expect(findFnDecl(program, "bar")!.name).toBe("bar");
    expect(findFnDecl(program, "missing")).toBeNull();
    expect(findTypeDecl(program, "Person")!.name).toBe("Person");
    expect(findTypeDecl(program, "Missing")).toBeNull();
    expect(findTypeMember(program, "Person", "name")).not.toBeNull();
    expect(findTypeMember(program, "Person", "x")).toBeNull();
    expect(findTypeMember(program, "NoType", "name")).toBeNull();
  });

  test("findConstructorCalleeAt returns type name on constructor call or null", () => {
    const withCall = new Parser("let x = Person(1, 2)").parse();
    expect(findConstructorCalleeAt(withCall, 1, 9)).toBe("Person");
    expect(findConstructorCalleeAt(new Parser("let x = 1").parse(), 1, 5)).toBeNull();
  });

  test("formatAstType: known kinds and fallbacks", () => {
    const num = { kind: "NamedType" as const, name: "number", loc: {} as any };
    const str = { kind: "NamedType" as const, name: "string", loc: {} as any };
    expect(formatAstType(undefined)).toBe("any");
    expect(formatAstType(num)).toBe("number");
    expect(formatAstType({ kind: "GenericType", name: "list", args: [num], loc: {} as any })).toBe("list[number]");
    expect(formatAstType({ kind: "UnionType", types: [num, str], loc: {} as any })).toBe("number | string");
    expect(formatAstType({ kind: "OptionalType", inner: num, loc: {} as any })).toBe("number?");
    expect(formatAstType({ kind: "FunctionType", params: [num], returnType: num, loc: {} as any })).toBe("fn(number): number");
    expect(formatAstType({ kind: "MapType", keyType: str, valueType: num, loc: {} as any } as any)).toBe("any");
  });

  test("formatFnSignature, formatMethodSignature, formatTypeSignature from AST", () => {
    const program = new Parser(`
fn add(a: number, b: number): number
  return a + b
type T
  x: number
  fn get(): number
`).parse();
    const fn = findFnDecl(program, "add")!;
    const typeDecl = findTypeDecl(program, "T")!;
    const method = typeDecl.body?.members?.find((m) => m.kind === "MethodDecl" && m.name === "get");
    expect(formatFnSignature(fn)).toContain("add");
    expect(formatFnSignature(fn)).toContain("number");
    expect(method).toBeDefined();
    expect(formatMethodSignature(method as any)).toContain("get");
    const out = formatTypeSignature(typeDecl);
    expect(out.signature).toBe("T");
    expect(out.fields).toContain("x: number");
  });

  test("formatFunctionType: function type or fn() fallback", () => {
    expect(formatFunctionType({ kind: "number" } as any)).toBe("fn()");
    const fnType = { kind: "function" as const, params: [{ name: "x", type: { kind: "number" } }], returnType: { kind: "string" } };
    expect(formatFunctionType(fnType as any)).toContain("x:");
    expect(formatFunctionType(fnType as any)).toContain("string");
  });

  test("getDocstring: first string literal or undefined", () => {
    const withDoc = new Parser("fn f()\n  \"doc here\"\n  return 1").parse();
    expect(getDocstring(findFnDecl(withDoc, "f")!.body)).toBe("doc here");
    expect(getDocstring(findFnDecl(new Parser("fn f()\n  return 1").parse(), "f")!.body)).toBeUndefined();
    expect(getDocstring(undefined)).toBeUndefined();
  });

  test("resolveObjectType: ref, optional, union, env, unknown ref", () => {
    const empty = new Parser("").parse();
    expect(resolveObjectType(empty, { kind: "ref", name: "NoSuchType" } as any)).toBeNull();
    const program = new Parser("type Person\n  name: string").parse();
    const ref = { kind: "ref" as const, name: "Person" };
    const resolved = resolveObjectType(program, ref);
    expect(resolved!.name).toBe("Person");
    expect(resolved!.properties.length).toBe(1);
    expect(resolveObjectType(program, { kind: "optional", inner: ref } as any)?.name).toBe("Person");
    const union = { kind: "union" as const, types: [ref, { kind: "number" }] };
    expect(resolveObjectType(program, union as any)?.name).toBe("Person");
    const result = new TypeChecker().check(program);
    expect(resolveObjectType(program, ref, result.env)?.name).toBe("Person");
  });

  test("formatTypeSignatureFromObject and parseQualifiedName / parseMemberQualifiedName", () => {
    const obj = { kind: "object" as const, name: "Person", properties: [{ name: "age", type: { kind: "number" }, optional: false, computed: false, defaultValue: false }], methods: [] };
    expect(formatTypeSignatureFromObject(obj as any).signature).toBe("Person");
    expect(formatTypeSignatureFromObject(obj as any).fields).toContain("age: number");
    expect(parseQualifiedName("a.b")).toEqual({ parent: "a", name: "b" });
    expect(parseQualifiedName("single")).toBeNull();
    expect(parseMemberQualifiedName("Type.member")).toEqual({ typeName: "Type", memberName: "member" });
    expect(parseMemberQualifiedName("nomember")).toBeNull();
  });
});
