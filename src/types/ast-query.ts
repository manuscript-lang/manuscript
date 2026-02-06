import * as AST from "../parser/ast";
import { visit } from "./ast-visitor";
import type { Type } from "./types";

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
    case "FnDecl": return 3;
    case "ExternFnDecl": return 10;
    case "TypeDecl": return 5;
    case "InterfaceDecl": return 10;
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
