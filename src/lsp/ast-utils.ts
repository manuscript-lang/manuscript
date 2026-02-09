// LSP-specific AST utilities - Scope-aware visitors, symbol collection, position-based queries
import * as AST from "../parser/ast";
import type { Type } from "../types/types";
import { visit } from "../types/ast-visitor";
import { findTypeDecl, findInterfaceDecl, findFnDecl } from "../types/ast-query";
import { getIterableElementType } from "../types/type-utils";

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
      case "SetExpr":
        for (const el of e.elements) expr(el, scope);
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
      case "IsExpr":
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

// ============================================
// LSP-specific AST queries
// ============================================

export function findConstructorCalleeAt(program: AST.Program, line: number, col: number): string | null {
  let result: string | null = null;
  visit(program, {
    expr(e) {
      if (e.kind === "CallExpr" && e.callee.kind === "Identifier") {
        const loc = e.callee.loc;
        const endCol = loc.column + e.callee.name.length;
        if (loc.line === line && loc.column <= col && col <= endCol) result = e.callee.name;
      }
    },
  });
  return result;
}

export function findVariableType(program: AST.Program, name: string, line: number): Type | null {
  function searchStatements(stmts: AST.Statement[]): Type | null {
    for (const s of stmts) {
      if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern" && s.pattern.name === name && s.loc.line === line) {
        return s.value.resolvedType || null;
      }
      if (s.kind === "VarStmt" && s.name === name && s.loc.line === line) {
        return s.value.resolvedType || null;
      }
      if (s.kind === "WithStmt") {
        for (const c of s.contexts) {
          if (c.name === name) return c.expr.resolvedType ?? null;
        }
        const inBody = searchStatements(s.body.statements);
        if (inBody) return inBody;
      }
      if (s.kind === "ForStmt" && s.pattern?.kind === "IdentifierPattern" && s.pattern.name === name && s.pattern.loc.line === line && s.iterable?.resolvedType) {
        return getIterableElementType(s.iterable.resolvedType);
      }
      if (s.kind === "ForStmt" && s.body) {
        const inBody = searchStatements(s.body.statements);
        if (inBody) return inBody;
      }
      if (s.kind === "FnDecl" && s.body) {
        const result = searchStatements(s.body.statements);
        if (result) return result;
      }
      if (s.kind === "TypeDecl") {
        for (const m of s.body?.members || []) {
          if (m.kind === "MethodDecl" && m.body) {
            const result = searchStatements(m.body.statements);
            if (result) return result;
          }
        }
      }
    }
    return null;
  }
  return searchStatements(program.body);
}

export function findParameterType(program: AST.Program, scope: string, paramName: string): AST.TypeExpr | null {
  if (scope.includes(".")) {
    const dotIdx = scope.indexOf(".");
    const typeName = scope.slice(0, dotIdx);
    const methodName = scope.slice(dotIdx + 1);
    const typeDecl = findTypeDecl(program, typeName);
    if (typeDecl) {
      for (const m of typeDecl.body?.members || []) {
        if (m.kind === "MethodDecl" && m.name === methodName) {
          for (const p of m.params) {
            if (p.name === paramName) return p.type ?? null;
          }
        }
      }
    }
    const iface = findInterfaceDecl(program, typeName);
    if (iface) {
      for (const m of iface.body?.members || []) {
        if (m.kind === "MethodDecl" && m.name === methodName) {
          for (const p of m.params) {
            if (p.name === paramName) return p.type ?? null;
          }
        }
      }
    }
  } else {
    const fn = findFnDecl(program, scope);
    if (fn) {
      for (const p of fn.params) {
        if (p.name === paramName) return p.type ?? null;
      }
    }
  }
  return null;
}

export function getReceiverTypeAtPosition(program: AST.Program, line: number, col: number, memberName: string): Type | undefined {
  let best: { type: Type; column: number } | null = null;
  const consider = (receiverType: Type | undefined, loc: AST.SourceLocation) => {
    if (!receiverType || loc.line !== line || loc.column > col) return;
    if (!best || loc.column >= best.column) best = { type: receiverType, column: loc.column };
  };
  visit(program, {
    expr(e) {
      if (e.kind === "MemberExpr" && e.property === memberName) consider(e.object.resolvedType, e.loc);
      if (e.kind === "CallExpr" && e.callee.kind === "MemberExpr" && e.callee.property === memberName)
        consider(e.callee.object.resolvedType, e.callee.loc);
    },
  });
  return best !== null ? (best as { type: Type; column: number }).type : undefined;
}
