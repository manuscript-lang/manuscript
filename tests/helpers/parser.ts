import { describe, test, expect } from "bun:test";
import { Parser } from "../../src/parser/parser";
import * as AST from "../../src/parser/ast";

/**
 * Parse a single expression
 */
export const expr = (src: string): AST.Expr => new Parser(src).parseExpression();

/**
 * Parse a single statement
 */
export const stmt = (src: string): AST.Statement => new Parser(src).parseStatement();

/**
 * Parse a full program
 */
export const program = (src: string): AST.Program => new Parser(src).parse();

/**
 * Table-driven expression tests
 */
export const exprCases = (cases: [string, Partial<AST.Expr>][]) => {
  cases.forEach(([input, expected]) => {
    test(`expr: ${input}`, () => {
      expect(expr(input)).toMatchObject(expected);
    });
  });
};

/**
 * Table-driven statement tests
 */
export const stmtCases = (cases: [string, Partial<AST.Statement>][]) => {
  cases.forEach(([input, expected]) => {
    test(`stmt: ${input}`, () => {
      expect(stmt(input)).toMatchObject(expected);
    });
  });
};

/**
 * Test that parser throws on invalid input
 */
export const expectParseError = (src: string, messageMatch?: string | RegExp) => {
  expect(() => new Parser(src).parse()).toThrow(messageMatch);
};

/**
 * Test that expression parser throws
 */
export const expectExprError = (src: string, messageMatch?: string | RegExp) => {
  expect(() => expr(src)).toThrow(messageMatch);
};

// ============================================
// AST Builder Helpers
// ============================================

/**
 * Create a binary expression
 */
export const binary = (op: string, left: Partial<AST.Expr>, right: Partial<AST.Expr>): Partial<AST.BinaryExpr> => ({
  kind: "BinaryExpr",
  op,
  left: left as AST.Expr,
  right: right as AST.Expr,
});

/**
 * Create a literal
 */
export const lit = (value: number | string | boolean | null): Partial<AST.Literal> => ({
  kind: "Literal",
  value,
});

/**
 * Create an identifier
 */
export const id = (name: string): Partial<AST.Identifier> => ({
  kind: "Identifier",
  name,
});

/**
 * Create a call expression
 */
export const call = (callee: Partial<AST.Expr>, ...args: Partial<AST.Expr>[]): Partial<AST.CallExpr> => ({
  kind: "CallExpr",
  callee: callee as AST.Expr,
  args: args as AST.Expr[],
});

/**
 * Create a member expression
 */
export const member = (object: Partial<AST.Expr>, property: string, optional = false): Partial<AST.MemberExpr> => ({
  kind: "MemberExpr",
  object: object as AST.Expr,
  property,
  optional,
});

/**
 * Create an index expression
 */
export const index = (object: Partial<AST.Expr>, idx: Partial<AST.Expr>): Partial<AST.IndexExpr> => ({
  kind: "IndexExpr",
  object: object as AST.Expr,
  index: idx as AST.Expr,
});

/**
 * Create a unary expression
 */
export const unary = (op: string, operand: Partial<AST.Expr>): Partial<AST.UnaryExpr> => ({
  kind: "UnaryExpr",
  op,
  operand: operand as AST.Expr,
});

/**
 * Create a list expression
 */
export const list = (...elements: Partial<AST.Expr>[]): Partial<AST.ListExpr> => ({
  kind: "ListExpr",
  elements: elements as AST.Expr[],
});

/**
 * Create a lambda expression
 */
export const lambda = (params: string[], body: Partial<AST.Expr>): Partial<AST.LambdaExpr> => ({
  kind: "LambdaExpr",
  params: params.map(name => ({ kind: "Parameter", name, optional: false, rest: false })) as AST.Parameter[],
  body: body as AST.Expr,
});

/**
 * Create a pipe expression
 */
export const pipe = (left: Partial<AST.Expr>, right: Partial<AST.Expr>): Partial<AST.PipeExpr> => ({
  kind: "PipeExpr",
  left: left as AST.Expr,
  right: right as AST.Expr,
});

/**
 * Create a range expression
 */
export const range = (start: Partial<AST.Expr>, end: Partial<AST.Expr>): Partial<AST.RangeExpr> => ({
  kind: "RangeExpr",
  start: start as AST.Expr,
  end: end as AST.Expr,
  inclusive: false,
});

/**
 * Create an if expression
 */
export const ifExpr = (condition: Partial<AST.Expr>, then: Partial<AST.Expr>, elseExpr: Partial<AST.Expr>): Partial<AST.IfExpr> => ({
  kind: "IfExpr",
  condition: condition as AST.Expr,
  then: then as AST.Expr,
  else: elseExpr as AST.Expr,
});
