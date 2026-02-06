// LSP Utilities - LSP-specific helpers only
// For type utilities, import directly from "../types/type-utils"
// For AST queries, import directly from "../types/ast-query"
import type { SymbolDef } from "./symbols";

// ============================================
// Location Matching
// ============================================

export function isLocationMatch(
  loc: { line: number; column: number },
  nameOffset: number,
  nameLength: number,
  line: number,
  column: number
): boolean {
  if (loc.line !== line) return false;
  const start = loc.column + nameOffset;
  const end = start + nameLength;
  return column >= start && column <= end;
}

export function isDefLocationMatch(def: SymbolDef, line: number, column: number): boolean {
  return isLocationMatch(def.loc, def.nameOffset, def.name.length, line, column);
}

// ============================================
// Qualified Name Parsing
// ============================================

export function parseQualifiedName(qn: string): { parent: string; name: string } | null {
  const lastDot = qn.lastIndexOf(".");
  if (lastDot < 0) return null;
  return { parent: qn.slice(0, lastDot), name: qn.slice(lastDot + 1) };
}

export function parseMemberQualifiedName(qn: string): { typeName: string; memberName: string } | null {
  const dotIdx = qn.indexOf(".");
  if (dotIdx < 0) return null;
  return { typeName: qn.slice(0, dotIdx), memberName: qn.slice(dotIdx + 1) };
}
