// AST Visitor - Generic traversal utilities for type checking passes
import * as AST from "../parser/ast";

// ============================================
// Basic Visitor Interface
// ============================================

export interface Visitor {
  // Called for each expression
  expr?(e: AST.Expr): void;
  // Called for each statement
  stmt?(s: AST.Statement): void;
  // Called when entering any node
  enter?(node: AST.ASTNode): void;
  // Called when leaving any node
  leave?(node: AST.ASTNode): void;
}

export function visit(program: AST.Program, visitor: Visitor): void {
  visitor.enter?.(program);
  for (const stmt of program.body) {
    visitStmt(stmt, visitor);
  }
  visitor.leave?.(program);
}

export function visitStmt(stmt: AST.Statement, visitor: Visitor): void {
  visitor.enter?.(stmt);
  visitor.stmt?.(stmt);

  switch (stmt.kind) {
    case "FnDecl":
      for (const p of stmt.params) {
        if (p.defaultValue) visitExpr(p.defaultValue, visitor);
      }
      visitBlock(stmt.body, visitor);
      break;
    case "TypeDecl":
      for (const member of stmt.body.members) {
        if (member.kind === "FieldDecl" && member.defaultValue) {
          visitExpr(member.defaultValue, visitor);
        }
        if (member.kind === "MethodDecl" && member.body) {
          visitBlock(member.body, visitor);
        }
      }
      break;
    case "TestDecl":
      if (stmt.withClause) visitExpr(stmt.withClause, visitor);
      visitBlock(stmt.body, visitor);
      break;
    case "LetStmt":
      visitExpr(stmt.value, visitor);
      break;
    case "VarStmt":
      visitExpr(stmt.value, visitor);
      break;
    case "AssignStmt":
      visitExpr(stmt.target, visitor);
      visitExpr(stmt.value, visitor);
      break;
    case "IfStmt":
      visitExpr(stmt.condition, visitor);
      if (stmt.then.kind === "Block") {
        visitBlock(stmt.then, visitor);
      } else {
        visitStmt(stmt.then, visitor);
      }
      for (const elseIf of stmt.elseIfs) {
        visitExpr(elseIf.condition, visitor);
        visitBlock(elseIf.body, visitor);
      }
      if (stmt.else) visitBlock(stmt.else, visitor);
      if (stmt.elseReturn) visitExpr(stmt.elseReturn, visitor);
      break;
    case "ForStmt":
      if (stmt.iterable) visitExpr(stmt.iterable, visitor);
      visitBlock(stmt.body, visitor);
      break;
    case "MatchStmt":
      visitExpr(stmt.value, visitor);
      for (const arm of stmt.arms) {
        if (arm.guard) visitExpr(arm.guard, visitor);
        if (arm.body.kind === "Block") {
          visitBlock(arm.body, visitor);
        } else {
          visitExpr(arm.body, visitor);
        }
      }
      break;
    case "ReturnStmt":
      if (stmt.value) visitExpr(stmt.value, visitor);
      break;
    case "YieldStmt":
      visitExpr(stmt.value, visitor);
      break;
    case "ThrowStmt":
      visitExpr(stmt.value, visitor);
      break;
    case "TryStmt":
      visitBlock(stmt.body, visitor);
      if (stmt.catch) visitBlock(stmt.catch.body, visitor);
      break;
    case "WithStmt":
      for (const ctx of stmt.contexts) {
        visitExpr(ctx.expr, visitor);
      }
      visitBlock(stmt.body, visitor);
      break;
    case "DeferStmt":
      visitStmt(stmt.body, visitor);
      break;
    case "ExprStmt":
      visitExpr(stmt.expr, visitor);
      break;
  }

  visitor.leave?.(stmt);
}

export function visitBlock(block: AST.Block, visitor: Visitor): void {
  visitor.enter?.(block);
  for (const stmt of block.statements) {
    visitStmt(stmt, visitor);
  }
  visitor.leave?.(block);
}

export function visitExpr(expr: AST.Expr, visitor: Visitor): void {
  visitor.enter?.(expr);
  visitor.expr?.(expr);

  switch (expr.kind) {
    case "BinaryExpr":
      visitExpr(expr.left, visitor);
      visitExpr(expr.right, visitor);
      break;
    case "UnaryExpr":
      visitExpr(expr.operand, visitor);
      break;
    case "CallExpr":
      visitExpr(expr.callee, visitor);
      for (const arg of expr.args) {
        const argExpr = "kind" in arg ? arg : arg.value;
        visitExpr(argExpr, visitor);
      }
      break;
    case "IndexExpr":
      visitExpr(expr.object, visitor);
      visitExpr(expr.index, visitor);
      if (expr.slice) {
        if (expr.slice.start) visitExpr(expr.slice.start, visitor);
        if (expr.slice.end) visitExpr(expr.slice.end, visitor);
        if (expr.slice.step) visitExpr(expr.slice.step, visitor);
      }
      break;
    case "MemberExpr":
      visitExpr(expr.object, visitor);
      break;
    case "PipeExpr":
      visitExpr(expr.left, visitor);
      visitExpr(expr.right, visitor);
      break;
    case "LambdaExpr":
      for (const p of expr.params) {
        if (p.defaultValue) visitExpr(p.defaultValue, visitor);
      }
      if (expr.body.kind === "Block") {
        visitBlock(expr.body, visitor);
      } else {
        visitExpr(expr.body, visitor);
      }
      break;
    case "IfExpr":
      visitExpr(expr.condition, visitor);
      visitExpr(expr.then, visitor);
      visitExpr(expr.else, visitor);
      break;
    case "MatchExpr":
      visitExpr(expr.value, visitor);
      for (const arm of expr.arms) {
        if (arm.guard) visitExpr(arm.guard, visitor);
        if (arm.body.kind === "Block") {
          visitBlock(arm.body, visitor);
        } else {
          visitExpr(arm.body, visitor);
        }
      }
      break;
    case "ListExpr":
      for (const el of expr.elements) {
        if (el.kind === "SpreadElement") {
          visitExpr(el.expr, visitor);
        } else {
          visitExpr(el, visitor);
        }
      }
      break;
    case "SetExpr":
      for (const el of expr.elements) visitExpr(el, visitor);
      break;
    case "MapExpr":
      for (const entry of expr.entries) {
        visitExpr(entry.key, visitor);
        visitExpr(entry.value, visitor);
      }
      break;
    case "TemplateLiteral":
      for (const part of expr.parts) {
        if (typeof part !== "string") {
          visitExpr(part.expr, visitor);
        }
      }
      break;
    case "SpawnExpr":
      visitExpr(expr.expr, visitor);
      break;
    case "IsExpr":
      visitExpr(expr.expr, visitor);
      break;
    case "TypeAssertion":
      visitExpr(expr.expr, visitor);
      break;
    case "NullAssertion":
      visitExpr(expr.expr, visitor);
      break;
    case "RangeExpr":
      visitExpr(expr.start, visitor);
      visitExpr(expr.end, visitor);
      break;
  }

  visitor.leave?.(expr);
}

// ============================================
// Reference checking utilities
// ============================================

// Check if an expression references a specific identifier
export function exprReferences(expr: AST.Expr, name: string): boolean {
  switch (expr.kind) {
    case "Identifier":
      return expr.name === name;
    case "CallExpr":
      if (exprReferences(expr.callee, name)) return true;
      for (const arg of expr.args) {
        const argExpr = "kind" in arg ? arg : arg.value;
        if (exprReferences(argExpr, name)) return true;
      }
      return false;
    case "LambdaExpr":
      if (expr.body.kind === "Block") {
        return blockReferences(expr.body, name);
      } else {
        return exprReferences(expr.body, name);
      }
    case "BinaryExpr":
      return exprReferences(expr.left, name) || exprReferences(expr.right, name);
    case "UnaryExpr":
      return exprReferences(expr.operand, name);
    case "MemberExpr":
      return exprReferences(expr.object, name);
    case "IndexExpr":
      return exprReferences(expr.object, name) || exprReferences(expr.index, name);
    case "IfExpr":
      return exprReferences(expr.condition, name) ||
        exprReferences(expr.then, name) ||
        exprReferences(expr.else, name);
    case "ListExpr":
      return expr.elements.some(e =>
        e.kind === "SpreadElement" ? exprReferences(e.expr, name) : exprReferences(e, name)
      );
    case "SetExpr":
      return expr.elements.some(e => exprReferences(e, name));
    case "MapExpr":
      return expr.entries.some(e => exprReferences(e.value, name));
    case "PipeExpr":
      return exprReferences(expr.left, name) || exprReferences(expr.right, name);
    case "SpawnExpr":
      return exprReferences(expr.expr, name);
    case "IsExpr":
      return exprReferences(expr.expr, name);
    case "TypeAssertion":
    case "NullAssertion":
      return exprReferences(expr.expr, name);
    default:
      return false;
  }
}

export function blockReferences(block: AST.Block, name: string): boolean {
  for (const stmt of block.statements) {
    if (stmtReferences(stmt, name)) return true;
  }
  return false;
}

export function stmtReferences(stmt: AST.Statement, name: string): boolean {
  switch (stmt.kind) {
    case "ExprStmt":
      return exprReferences(stmt.expr, name);
    case "LetStmt":
    case "VarStmt":
      return exprReferences(stmt.value, name);
    case "AssignStmt":
      return exprReferences(stmt.value, name);
    case "ReturnStmt":
      return stmt.value ? exprReferences(stmt.value, name) : false;
    case "IfStmt": {
      const thenRefs = stmt.then.kind === "Block"
        ? blockReferences(stmt.then, name)
        : stmtReferences(stmt.then, name);
      const elseRefs = stmt.else ? blockReferences(stmt.else, name) : false;
      return exprReferences(stmt.condition, name) || thenRefs || elseRefs;
    }
    case "ForStmt":
      return (stmt.iterable ? exprReferences(stmt.iterable, name) : false) ||
        blockReferences(stmt.body, name);
    default:
      return false;
  }
}
