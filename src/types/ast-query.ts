import * as AST from "../parser/ast";
import { visit } from "./ast-visitor";
import type { Type } from "./types";
import { NAME_OFFSET_FN, NAME_OFFSET_EXTERN_FN, NAME_OFFSET_TYPE, NAME_OFFSET_INTERFACE } from "../shared/constants";

export function findFnDecl(program: AST.Program, name: string): AST.FnDecl | null {
  for (const s of program.body) {
    if (s.kind === "FnDecl" && s.name === name) return s;
  }
  return null;
}

export function findTypeDecl(program: AST.Program, name: string): AST.TypeDecl | null {
  for (const s of program.body) {
    if (s.kind === "TypeDecl" && s.name === name) return s;
  }
  return null;
}

export function findInterfaceDecl(program: AST.Program, name: string): AST.InterfaceDecl | null {
  for (const s of program.body) {
    if (s.kind === "InterfaceDecl" && s.name === name) return s;
  }
  return null;
}

export function findTypeMember(program: AST.Program, typeName: string, memberName: string): AST.FieldDecl | AST.MethodDecl | null {
  const typeDecl = findTypeDecl(program, typeName);
  if (!typeDecl) return null;
  for (const m of typeDecl.body?.members || []) {
    if ((m.kind === "FieldDecl" || m.kind === "MethodDecl") && m.name === memberName) return m;
  }
  return null;
}

export type TopLevelDecl = AST.FnDecl | AST.ExternFnDecl | AST.TypeDecl | AST.InterfaceDecl;

function nameOffsetForDecl(decl: TopLevelDecl): number {
  switch (decl.kind) {
    case "FnDecl": return NAME_OFFSET_FN;
    case "ExternFnDecl": return NAME_OFFSET_EXTERN_FN;
    case "TypeDecl": return NAME_OFFSET_TYPE;
    case "InterfaceDecl": return NAME_OFFSET_INTERFACE;
    default: return 0;
  }
}

export function findDeclByName(program: AST.Program, name: string): { decl: TopLevelDecl; nameOffset: number } | null {
  for (const s of program.body) {
    if ((s.kind === "FnDecl" || s.kind === "ExternFnDecl" || s.kind === "TypeDecl" || s.kind === "InterfaceDecl") && s.name === name) {
      return { decl: s, nameOffset: nameOffsetForDecl(s) };
    }
  }
  return null;
}

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
