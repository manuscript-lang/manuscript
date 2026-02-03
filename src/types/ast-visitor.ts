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
// Scope-aware visitor (for IDE features like references/rename)
// ============================================

export interface ScopedVisitor {
  onIdent?: (name: string, loc: AST.SourceLocation, scope: string) => void;
  onMember?: (prop: string, loc: AST.SourceLocation) => void;
}

export function visitWithScope(program: AST.Program, v: ScopedVisitor): void {
  function expr(e: AST.Expr | undefined, scope: string): void {
    if (!e) return;
    switch (e.kind) {
      case "Identifier":
        v.onIdent?.(e.name, e.loc, scope);
        break;
      case "MemberExpr":
        v.onMember?.(e.property, e.loc);
        expr(e.object, scope);
        break;
      case "CallExpr":
        expr(e.callee, scope);
        for (const a of e.args) expr("kind" in a ? a : a.value, scope);
        break;
      case "BinaryExpr":
      case "PipeExpr":
        expr(e.left, scope);
        expr(e.right, scope);
        break;
      case "UnaryExpr":
        expr(e.operand, scope);
        break;
      case "IndexExpr":
        expr(e.object, scope);
        expr(e.index, scope);
        if (e.slice) {
          expr(e.slice.start, scope);
          expr(e.slice.end, scope);
          expr(e.slice.step, scope);
        }
        break;
      case "LambdaExpr":
        if (e.body.kind === "Block") block(e.body, scope);
        else expr(e.body, scope);
        break;
      case "IfExpr":
        expr(e.condition, scope);
        expr(e.then, scope);
        expr(e.else, scope);
        break;
      case "ListExpr":
        for (const el of e.elements) {
          if (el.kind === "SpreadElement") expr(el.expr, scope);
          else expr(el, scope);
        }
        break;
      case "MapExpr":
        for (const en of e.entries) {
          expr(en.key, scope);
          expr(en.value, scope);
        }
        break;
      case "RangeExpr":
        expr(e.start, scope);
        expr(e.end, scope);
        break;
      case "MatchExpr":
        expr(e.value, scope);
        for (const arm of e.arms) {
          if (arm.guard) expr(arm.guard, scope);
          if (arm.body.kind === "Block") block(arm.body, scope);
          else expr(arm.body, scope);
        }
        break;
      case "TemplateLiteral":
        for (const p of e.parts) {
          if (typeof p !== "string") expr(p.expr, scope);
        }
        break;
      case "SpawnExpr":
      case "TypeAssertion":
      case "NullAssertion":
        expr(e.expr, scope);
        break;
    }
  }

  function block(b: AST.Block | undefined, scope: string): void {
    if (!b?.statements) return;
    for (const s of b.statements) stmt(s, scope);
  }

  function stmt(s: AST.Statement, scope: string): void {
    switch (s.kind) {
      case "FnDecl":
        block(s.body, s.name);
        break;
      case "TypeDecl":
        for (const m of s.body?.members || []) {
          if (m.kind === "MethodDecl" && m.body) block(m.body, `${s.name}.${m.name}`);
          if (m.kind === "FieldDecl" && m.defaultValue) expr(m.defaultValue, s.name);
        }
        break;
      case "LetStmt":
      case "VarStmt":
        expr(s.value, scope);
        break;
      case "AssignStmt":
        expr(s.target, scope);
        expr(s.value, scope);
        break;
      case "ExprStmt":
        expr(s.expr, scope);
        break;
      case "IfStmt":
        expr(s.condition, scope);
        if (s.then.kind === "Block") block(s.then, scope);
        else stmt(s.then, scope);
        for (const elif of s.elseIfs) {
          expr(elif.condition, scope);
          block(elif.body, scope);
        }
        if (s.else) block(s.else, scope);
        if (s.elseReturn) expr(s.elseReturn, scope);
        break;
      case "ForStmt":
        expr(s.iterable, scope);
        block(s.body, scope);
        break;
      case "MatchStmt":
        expr(s.value, scope);
        for (const arm of s.arms) {
          if (arm.guard) expr(arm.guard, scope);
          if (arm.body.kind === "Block") block(arm.body, scope);
          else expr(arm.body, scope);
        }
        break;
      case "ReturnStmt":
        expr(s.value, scope);
        break;
      case "YieldStmt":
      case "ThrowStmt":
        expr(s.value, scope);
        break;
      case "TryStmt":
        block(s.body, scope);
        if (s.catch?.body) block(s.catch.body, scope);
        break;
      case "WithStmt":
        for (const ctx of s.contexts) expr(ctx.expr, scope);
        block(s.body, scope);
        break;
      case "DeferStmt":
        stmt(s.body, scope);
        break;
      case "TestDecl":
        if (s.withClause) expr(s.withClause, scope);
        block(s.body, "test");
        break;
    }
  }

  for (const s of program.body) stmt(s, "");
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
    case "MapExpr":
      return expr.entries.some(e => exprReferences(e.value, name));
    case "PipeExpr":
      return exprReferences(expr.left, name) || exprReferences(expr.right, name);
    case "SpawnExpr":
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

// ============================================
// Symbol Collection (for IDE features)
// ============================================

export interface DocumentSymbol {
  name: string;
  kind: "function" | "type" | "variable" | "parameter" | "field" | "method";
  scope: string;
  loc: AST.SourceLocation;
  nameOffset?: number;
}

export function collectSymbols(program: AST.Program): DocumentSymbol[] {
  const syms: DocumentSymbol[] = [];
  const add = (name: string, kind: DocumentSymbol["kind"], scope: string, loc: AST.SourceLocation, nameOffset = 0) =>
    syms.push({ name, kind, scope, loc, nameOffset });

  function walkBlock(b: AST.Block | undefined, scope: string) {
    if (!b?.statements) return;
    for (const s of b.statements) {
      if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern") {
        add(s.pattern.name, "variable", scope, s.loc, 4);
      } else if (s.kind === "VarStmt") {
        add(s.name, "variable", scope, s.loc, 4);
      } else if (s.kind === "ForStmt" && s.pattern?.kind === "IdentifierPattern") {
        add(s.pattern.name, "variable", scope, s.pattern.loc);
      }
    }
  }

  for (const s of program.body) {
    if (s.kind === "FnDecl") {
      add(s.name, "function", "", s.loc, 3);
      for (const p of s.params) add(p.name, "parameter", s.name, p.loc);
      walkBlock(s.body, s.name);
    } else if (s.kind === "TypeDecl") {
      add(s.name, "type", "", s.loc, 5);
      for (const m of s.body?.members || []) {
        if (m.kind === "FieldDecl") {
          add(m.name, "field", s.name, m.loc);
        } else if (m.kind === "MethodDecl") {
          const scope = `${s.name}.${m.name}`;
          add(m.name, "method", s.name, m.loc, 3);
          for (const p of m.params) add(p.name, "parameter", scope, p.loc);
          if (m.body) walkBlock(m.body, scope);
        }
      }
    } else if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern") {
      add(s.pattern.name, "variable", "", s.loc, 4);
    } else if (s.kind === "VarStmt") {
      add(s.name, "variable", "", s.loc, 4);
    } else if (s.kind === "TestDecl") {
      walkBlock(s.body, "test");
    }
  }

  return syms;
}

export function findScope(program: AST.Program, line: number): { scope: string; typeName?: string } {
  for (const s of program.body) {
    if (s.loc.line > line) break;
    if (s.kind === "TypeDecl") {
      for (const m of s.body?.members || []) {
        if (m.kind === "MethodDecl" && m.body && m.loc.line <= line) {
          return { scope: `${s.name}.${m.name}`, typeName: s.name };
        }
      }
      if (s.body?.members?.length) return { scope: s.name, typeName: s.name };
    } else if (s.kind === "FnDecl" && s.loc.line <= line) {
      return { scope: s.name };
    }
  }
  return { scope: "" };
}

// ============================================
// Position-based Node Finding
// ============================================

export interface NodeAtPosition {
  node: AST.ASTNode;
  kind: "Identifier" | "Parameter" | "FnDecl" | "TypeDecl" | "LetBinding" | "VarBinding" | "ForBinding";
}

export function findNodeAtPosition(program: AST.Program, line: number, col: number): NodeAtPosition | null {
  let best: NodeAtPosition | null = null;

  function check(node: any, kind: NodeAtPosition["kind"]) {
    if (!node?.loc) return;
    if (node.loc.line === line && node.loc.column <= col) {
      if (!best || node.loc.column >= (best.node as any).loc.column) {
        best = { node, kind };
      }
    }
  }

  function checkIdentifier(e: AST.Expr) {
    if (e.kind === "Identifier") {
      const endCol = e.loc.column + e.name.length;
      if (e.loc.line === line && e.loc.column <= col && col <= endCol) {
        check(e, "Identifier");
      }
    }
  }

  function checkBindingSites(s: AST.Statement) {
    if (s.kind === "FnDecl") {
      const nameStart = s.loc.column + 3;
      if (s.loc.line === line && nameStart <= col && col <= nameStart + s.name.length) {
        check(s, "FnDecl");
      }
      for (const p of s.params) {
        const endCol = p.loc.column + p.name.length;
        if (p.loc.line === line && p.loc.column <= col && col <= endCol) {
          check(p, "Parameter");
        }
      }
    } else if (s.kind === "TypeDecl") {
      const nameStart = s.loc.column + 5;
      if (s.loc.line === line && nameStart <= col && col <= nameStart + s.name.length) {
        check(s, "TypeDecl");
      }
      for (const m of s.body?.members || []) {
        if (m.kind === "MethodDecl") {
          for (const p of m.params) {
            const endCol = p.loc.column + p.name.length;
            if (p.loc.line === line && p.loc.column <= col && col <= endCol) {
              check(p, "Parameter");
            }
          }
        }
      }
    } else if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern") {
      const nameStart = s.loc.column + 4;
      if (s.loc.line === line && nameStart <= col && col <= nameStart + s.pattern.name.length) {
        check({ ...s, name: s.pattern.name }, "LetBinding");
      }
    } else if (s.kind === "VarStmt") {
      const nameStart = s.loc.column + 4;
      if (s.loc.line === line && nameStart <= col && col <= nameStart + s.name.length) {
        check(s, "VarBinding");
      }
    } else if (s.kind === "ForStmt" && s.pattern?.kind === "IdentifierPattern") {
      const endCol = s.pattern.loc.column + s.pattern.name.length;
      if (s.pattern.loc.line === line && s.pattern.loc.column <= col && col <= endCol) {
        check({ ...s.pattern, iterable: s.iterable }, "ForBinding");
      }
    }
  }

  visit(program, {
    expr: checkIdentifier,
    stmt: checkBindingSites,
  });

  return best;
}
