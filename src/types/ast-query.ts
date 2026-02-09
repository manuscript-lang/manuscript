import * as AST from "../parser/ast";
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

