// Init Pass - Inserts default init for non-inherited types, validates init/super for inherited types
import * as AST from "../../parser/ast";
import { TypeCheckError } from "../errors";
import { TypeErrors } from "../../shared/errors";

export interface InitPassResult {
  errors: TypeCheckError[];
}

export function initPass(program: AST.Program): InitPassResult {
  const errors: TypeCheckError[] = [];

  for (const stmt of program.body) {
    if (stmt.kind === "TypeDecl") {
      processTypeInit(stmt, errors);
    }
  }

  return { errors };
}

function processTypeInit(decl: AST.TypeDecl, errors: TypeCheckError[]): void {
  if (!decl.body) return;

  const hasExtends = decl.extends && decl.extends.length > 0;
  const initDecl = decl.body.members.find((m): m is AST.InitDecl => m.kind === "InitDecl");

  if (hasExtends) {
    // Inherited types MUST have explicit init
    const parentName = decl.extends![0]!.kind === "NamedType" ? decl.extends![0]!.name : "parent";
    if (!initDecl) {
      const err = TypeErrors.inheritedTypeMissingInit(decl.name, parentName);
      errors.push(new TypeCheckError(err.message, decl.loc, err.hint));
      return;
    }
    // Init must call super()
    if (!hasSuperCall(initDecl.body)) {
      const err = TypeErrors.initMissingSuperCall(decl.name);
      errors.push(new TypeCheckError(err.message, initDecl.loc, err.hint));
    }
  } else {
    // Non-inherited types: insert default init if missing
    if (!initDecl) {
      decl.body.members.push(createDefaultInit(decl));
    }
  }

  // Validate super() only appears in init blocks (check methods)
  validateNoSuperOutsideInit(decl, errors);
}

function hasSuperCall(block: AST.Block): boolean {
  for (const stmt of block.statements) {
    if (stmt.kind === "ExprStmt" && stmt.expr.kind === "SuperExpr") {
      return true;
    }
  }
  return false;
}

function createDefaultInit(decl: AST.TypeDecl): AST.InitDecl {
  const fields = decl.body!.members.filter((m): m is AST.FieldDecl => m.kind === "FieldDecl");
  
  // Required: non-optional, no default, not computed
  const required = fields.filter(f => !f.optional && !f.defaultValue && !f.computed);
  // Optional: optional, has default, or computed (computed fields have defaultValue from their expression)
  const optional = fields.filter(f => f.optional || f.defaultValue || f.computed);

  const allFields = [...required, ...optional];
  
  const params: AST.Parameter[] = allFields.map(f => ({
    kind: "Parameter" as const,
    name: f.name,
    type: f.type,
    optional: f.optional || !!f.defaultValue || f.computed,
    defaultValue: f.defaultValue,
    rest: false,
    loc: f.loc,
  }));

  // Generate assignment statements: fieldName = fieldName
  const statements: AST.Statement[] = allFields.map(f => ({
    kind: "AssignStmt" as const,
    target: { kind: "Identifier" as const, name: f.name, loc: f.loc },
    value: { kind: "Identifier" as const, name: f.name, loc: f.loc },
    op: "=",
    loc: f.loc,
  }));

  return {
    kind: "InitDecl",
    params,
    body: { kind: "Block", statements, loc: decl.loc },
    loc: decl.loc,
  };
}

function validateNoSuperOutsideInit(decl: AST.TypeDecl, errors: TypeCheckError[]): void {
  if (!decl.body) return;

  for (const member of decl.body.members) {
    if (member.kind === "MethodDecl" && member.body) {
      checkBlockForSuper(member.body, errors);
    }
  }
}

function checkBlockForSuper(block: AST.Block, errors: TypeCheckError[]): void {
  for (const stmt of block.statements) {
    checkStmtForSuper(stmt, errors);
  }
}

function checkBodyForSuper(body: AST.Block | AST.Expr, errors: TypeCheckError[]): void {
  if (body.kind === "Block") {
    checkBlockForSuper(body, errors);
  } else {
    checkExprForSuper(body, errors);
  }
}

function checkStmtForSuper(stmt: AST.Statement, errors: TypeCheckError[]): void {
  switch (stmt.kind) {
    case "ExprStmt":
      checkExprForSuper(stmt.expr, errors);
      break;
    case "LetStmt":
    case "VarStmt":
      if (stmt.value) checkExprForSuper(stmt.value, errors);
      break;
    case "AssignStmt":
      checkExprForSuper(stmt.value, errors);
      break;
    case "IfStmt":
      checkExprForSuper(stmt.condition, errors);
      if (stmt.then.kind === "Block") checkBlockForSuper(stmt.then, errors);
      for (const elif of stmt.elseIfs) {
        checkExprForSuper(elif.condition, errors);
        checkBlockForSuper(elif.body, errors);
      }
      if (stmt.else) checkBlockForSuper(stmt.else, errors);
      break;
    case "ForStmt":
      if (stmt.iterable) checkExprForSuper(stmt.iterable, errors);
      checkBlockForSuper(stmt.body, errors);
      break;
    case "MatchStmt":
      checkExprForSuper(stmt.value, errors);
      for (const arm of stmt.arms) {
        if (arm.guard) checkExprForSuper(arm.guard, errors);
        checkBodyForSuper(arm.body, errors);
      }
      break;
    case "ReturnStmt":
      if (stmt.value) checkExprForSuper(stmt.value, errors);
      break;
    case "TryStmt":
      checkBlockForSuper(stmt.body, errors);
      if (stmt.catch) checkBlockForSuper(stmt.catch.body, errors);
      break;
    case "ThrowStmt":
      checkExprForSuper(stmt.value, errors);
      break;
    case "WithStmt":
      for (const ctx of stmt.contexts) {
        checkExprForSuper(ctx.expr, errors);
      }
      checkBlockForSuper(stmt.body, errors);
      break;
  }
}

function checkExprForSuper(expr: AST.Expr, errors: TypeCheckError[]): void {
  if (expr.kind === "SuperExpr") {
    const err = TypeErrors.superOutsideInit();
    errors.push(new TypeCheckError(err.message, expr.loc, err.hint));
    return;
  }

  switch (expr.kind) {
    case "BinaryExpr":
      checkExprForSuper(expr.left, errors);
      checkExprForSuper(expr.right, errors);
      break;
    case "UnaryExpr":
      checkExprForSuper(expr.operand, errors);
      break;
    case "CallExpr":
      checkExprForSuper(expr.callee, errors);
      for (const arg of expr.args) {
        if ("value" in arg && "name" in arg) {
          checkExprForSuper(arg.value, errors);
        } else {
          checkExprForSuper(arg as AST.Expr, errors);
        }
      }
      break;
    case "MemberExpr":
      checkExprForSuper(expr.object, errors);
      break;
    case "IndexExpr":
      checkExprForSuper(expr.object, errors);
      checkExprForSuper(expr.index, errors);
      break;
    case "LambdaExpr":
      checkBodyForSuper(expr.body, errors);
      break;
    case "IfExpr":
      checkExprForSuper(expr.condition, errors);
      checkExprForSuper(expr.then, errors);
      if (expr.else) checkExprForSuper(expr.else, errors);
      break;
    case "MatchExpr":
      checkExprForSuper(expr.value, errors);
      for (const arm of expr.arms) {
        if (arm.guard) checkExprForSuper(arm.guard, errors);
        checkBodyForSuper(arm.body, errors);
      }
      break;
    case "ListExpr":
      for (const el of expr.elements) {
        if (el.kind === "SpreadElement") {
          checkExprForSuper(el.expr, errors);
        } else {
          checkExprForSuper(el, errors);
        }
      }
      break;
    case "MapExpr":
      for (const entry of expr.entries) {
        if (entry.spread) {
          checkExprForSuper(entry.value, errors);
        } else {
          checkExprForSuper(entry.key, errors);
          checkExprForSuper(entry.value, errors);
        }
      }
      break;
    case "PipeExpr":
      checkExprForSuper(expr.left, errors);
      checkExprForSuper(expr.right, errors);
      break;
    case "SpawnExpr":
      checkExprForSuper(expr.expr, errors);
      break;
    case "TemplateLiteral":
      for (const part of expr.parts) {
        if (typeof part !== "string") {
          checkExprForSuper(part.expr, errors);
        }
      }
      break;
    case "RangeExpr":
      checkExprForSuper(expr.start, errors);
      checkExprForSuper(expr.end, errors);
      break;
    case "NullAssertion":
      checkExprForSuper(expr.expr, errors);
      break;
    case "TypeAssertion":
      checkExprForSuper(expr.expr, errors);
      break;
  }
}
