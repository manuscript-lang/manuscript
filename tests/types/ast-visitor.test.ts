import { describe, test, expect } from "bun:test";
import {
  visit,
  visitStmt,
  visitExpr,
  visitBlock,
  visitWithScope,
  exprReferences,
  blockReferences,
  stmtReferences,
  collectSymbols,
  findScope,
  findNodeAtPosition,
} from "../../src/types/ast-visitor";
import { Parser } from "../../src/parser";
import type * as AST from "../../src/parser/ast";

function parse(source: string): AST.Program {
  return new Parser(source).parse();
}

describe("AST Visitor", () => {
  test("visit calls enter/leave and stmt/expr for program", () => {
    const program = parse("let x = 1");
    const entered: string[] = [];
    const left: string[] = [];
    visit(program, {
      enter(n) {
        entered.push(n.kind);
      },
      leave(n) {
        left.push(n.kind);
      },
      stmt(s) {
        entered.push(`stmt:${s.kind}`);
      },
      expr(e) {
        entered.push(`expr:${e.kind}`);
      },
    });
    expect(entered).toContain("Program");
    expect(entered).toContain("stmt:LetStmt");
    expect(entered).toContain("expr:Literal");
    expect(left).toContain("Program");
  });

  test("visitStmt covers FnDecl, TypeDecl, TestDecl, LetStmt, VarStmt, AssignStmt", () => {
    const program = parse(`
fn f(a: number = 0): number
  return a
type T
  x: number = 1
  fn m(): number
    return 0
test "t" with testing()
  assert true
let a = 1
var b = 2
a = 3
`);
    const kinds: string[] = [];
    visit(program, { stmt(s) { kinds.push(s.kind); } });
    expect(kinds).toContain("FnDecl");
    expect(kinds).toContain("TypeDecl");
    expect(kinds).toContain("TestDecl");
    expect(kinds).toContain("LetStmt");
    expect(kinds).toContain("VarStmt");
    expect(kinds).toContain("AssignStmt");
  });

  test("visitStmt covers IfStmt, ForStmt, MatchStmt", () => {
    const program = parse(`
fn f(x: number): number
  if x > 0
    return 1
  else
    return 0
fn g(x: number): number
  for i in range(0, 10)
    return i
fn h(x: number): number
  match x
    1 => 1
    _ => 0
`);
    const kinds: string[] = [];
    visit(program, { stmt(s) { kinds.push(s.kind); } });
    expect(kinds).toContain("IfStmt");
    expect(kinds).toContain("ForStmt");
    expect(kinds).toContain("MatchStmt");
    expect(kinds).toContain("ReturnStmt");
  });

  test("visitStmt covers ReturnStmt, YieldStmt, ThrowStmt, TryStmt, WithStmt, DeferStmt, ExprStmt", () => {
    const program = parse(`
fn f(): number
  return 1
gen fn g(): number
  yield 1
fn h()
  try
    throw error("x")
  catch e
    return
fn w()
  with let c = testing()
    return
  defer print(1)
  print(2)
`);
    const kinds: string[] = [];
    visit(program, { stmt(s) { kinds.push(s.kind); } });
    expect(kinds).toContain("ReturnStmt");
    expect(kinds).toContain("YieldStmt");
    expect(kinds).toContain("ThrowStmt");
    expect(kinds).toContain("TryStmt");
    expect(kinds).toContain("WithStmt");
    expect(kinds).toContain("DeferStmt");
    expect(kinds).toContain("ExprStmt");
  });

  test("visitExpr covers BinaryExpr, UnaryExpr, CallExpr, IndexExpr with slice, MemberExpr, PipeExpr", () => {
    const program = parse(`
let a = 1 + 2
let b = -a
let c = print(1)
let d = [1,2,3][1:2:1]
let e = a.foo
let f = 1 | double
`);
    const kinds: string[] = [];
    visit(program, { expr(e) { kinds.push(e.kind); } });
    expect(kinds).toContain("BinaryExpr");
    expect(kinds).toContain("UnaryExpr");
    expect(kinds).toContain("CallExpr");
    expect(kinds).toContain("IndexExpr");
    expect(kinds).toContain("MemberExpr");
    expect(kinds).toContain("PipeExpr");
  });

  test("visitExpr covers LambdaExpr, IfExpr, MatchExpr, ListExpr with spread, MapExpr, TemplateLiteral", () => {
    const program = parse(`
let a = (x: number) => x
let b = if true then 1 else 0
let c = match 1
  1 => 1
  _ => 0
let d = [1, 2, 3]
let e = { a: 1 }
let f = "hi"
`);
    const kinds: string[] = [];
    visit(program, { expr(e) { kinds.push(e.kind); } });
    expect(kinds).toContain("LambdaExpr");
    expect(kinds).toContain("IfExpr");
    expect(kinds).toContain("MatchExpr");
    expect(kinds).toContain("ListExpr");
    expect(kinds).toContain("MapExpr");
  });

  test("visitExpr covers TemplateLiteral and ListExpr SpreadElement", () => {
    const program = parse(`
let x = 1
let s = "hi {x}"
let l = [1, ...[]]
`);
    const kinds: string[] = [];
    visit(program, { expr(e) { kinds.push(e.kind); } });
    expect(kinds).toContain("TemplateLiteral");
    expect(kinds).toContain("ListExpr");
  });

  test("visitExpr covers SpawnExpr, TypeAssertion, NullAssertion, RangeExpr", () => {
    const program = parse(`
let a = spawn foo()
let b = x as number
let c = maybe!
let d = 1..10
`);
    const kinds: string[] = [];
    visit(program, { expr(e) { kinds.push(e.kind); } });
    expect(kinds).toContain("SpawnExpr");
    expect(kinds).toContain("TypeAssertion");
    expect(kinds).toContain("NullAssertion");
    expect(kinds).toContain("RangeExpr");
  });

  test("visitWithScope calls onIdent and onMember", () => {
    const program = parse(`
let x = 1
let y = x + 1
let z = y.foo
`);
    const idents: string[] = [];
    const members: string[] = [];
    visitWithScope(program, {
      onIdent(name) { idents.push(name); },
      onMember(prop) { members.push(prop); },
    });
    expect(idents).toContain("x");
    expect(idents).toContain("y");
    expect(members).toContain("foo");
  });

  test("exprReferences finds name in Identifier, CallExpr, LambdaExpr, BinaryExpr, MapExpr, etc", () => {
    const program = parse("let x = 1\nlet y = x + foo(x)");
    const letStmt = program.body[1] as AST.LetStmt;
    expect(exprReferences(letStmt.value, "x")).toBe(true);
    expect(exprReferences(letStmt.value, "foo")).toBe(true);
    expect(exprReferences(letStmt.value, "missing")).toBe(false);
    const withLambda = parse("let f = (z: number) => z");
    const lambdaStmt = withLambda.body[0] as AST.LetStmt;
    expect(exprReferences(lambdaStmt.value, "z")).toBe(true);
    const withMap = parse("let m = { a: key }");
    const mapStmt = withMap.body[0] as AST.LetStmt;
    expect(exprReferences(mapStmt.value, "key")).toBe(true);
  });

  test("blockReferences and stmtReferences", () => {
    const program = parse(`
fn f(): number
  let x = 1
  return x
`);
    const fn = program.body[0] as AST.FnDecl;
    expect(fn.body).not.toBeNull();
    expect(blockReferences(fn.body!, "x")).toBe(true);
    expect(blockReferences(fn.body!, "y")).toBe(false);
    const returnStmt = fn.body!.statements[1] as AST.ReturnStmt;
    expect(stmtReferences(returnStmt, "x")).toBe(true);
    const withFor = parse(`
fn g(): number
  for i in items
    return i
`);
    const forFn = withFor.body[0] as AST.FnDecl;
    const forStmt = forFn.body!.statements[0] as AST.ForStmt;
    expect(stmtReferences(forStmt, "items")).toBe(true);
    expect(stmtReferences(forStmt, "i")).toBe(true);
  });

  test("collectSymbols returns functions, types, variables, parameters, fields, methods", () => {
    const program = parse(`
fn add(a: number, b: number): number
  return a + b
type T
  x: number
  fn get(): number
    return x
let top = 1
test "t"
  let local = 2
`);
    const syms = collectSymbols(program);
    expect(syms.some((s) => s.kind === "function" && s.name === "add")).toBe(true);
    expect(syms.some((s) => s.kind === "type" && s.name === "T")).toBe(true);
    expect(syms.some((s) => s.kind === "parameter" && s.name === "a")).toBe(true);
    expect(syms.some((s) => s.kind === "field" && s.name === "x")).toBe(true);
    expect(syms.some((s) => s.kind === "method" && s.name === "get")).toBe(true);
    expect(syms.some((s) => s.kind === "variable" && s.name === "top")).toBe(true);
  });

  test("findScope returns scope for line in function, type, method", () => {
    const withTypeFirst = parse(`
type T
  x: number
  fn m(): number
    return 0
fn foo(): number
  return 0
`);
    expect(findScope(withTypeFirst, 2).scope).toBe("T");
    expect(findScope(withTypeFirst, 4).scope).toBe("T.m");
    expect(findScope(withTypeFirst, 4).typeName).toBe("T");
    expect(findScope(withTypeFirst, 1).scope).toBe("");
    const withFnFirst = parse(`
fn foo(): number
  return 0
`);
    expect(findScope(withFnFirst, 2).scope).toBe("foo");
  });

  test("findNodeAtPosition returns Identifier, Parameter, FnDecl, TypeDecl, LetBinding, VarBinding, ForBinding", () => {
    const source = `
fn bar(x: number): number
  return x
type Box
  value: number
let a = 1
var b = 2
for i in range(0, 1)
  print(i)
`;
    const program = parse(source);
    const atBar = findNodeAtPosition(program, 2, 4);
    expect(atBar?.kind).toBe("FnDecl");
    const atParam = findNodeAtPosition(program, 2, 8);
    expect(atParam?.kind).toBe("Parameter");
    const atBox = findNodeAtPosition(program, 4, 6);
    expect(atBox?.kind).toBe("TypeDecl");
    const atLet = findNodeAtPosition(program, 6, 5);
    expect(atLet?.kind).toBe("LetBinding");
    const atVar = findNodeAtPosition(program, 7, 5);
    expect(atVar?.kind).toBe("VarBinding");
    const atFor = findNodeAtPosition(program, 8, 5);
    expect(atFor?.kind).toBe("ForBinding");
    const atIdent = findNodeAtPosition(program, 9, 7);
    expect(atIdent?.kind).toBe("Identifier");
  });
});
