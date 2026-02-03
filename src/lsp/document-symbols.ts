// Document Symbols - Provides document outline information
import type { SourceLocation } from "../parser/ast";
import type { SymbolTable, SymbolDef, SymbolId } from "./symbols";

export type DocumentSymbolKind = "function" | "type" | "field" | "method" | "variable" | "parameter";

export interface DocumentSymbolInfo {
  name: string;
  kind: DocumentSymbolKind;
  loc: SourceLocation;
  nameOffset: number;
  // Parent symbol (for nested symbols like fields/methods inside types)
  parent?: string;
}

// Get all document-level symbols for outline view
export function getDocumentSymbols(symbols: SymbolTable): DocumentSymbolInfo[] {
  const result: DocumentSymbolInfo[] = [];
  
  for (const def of symbols.getAllDefinitions()) {
    // Only include top-level and type member symbols (skip local variables/parameters)
    if (shouldIncludeInOutline(def)) {
      result.push({
        name: def.name,
        kind: def.id.kind,
        loc: def.loc,
        nameOffset: def.nameOffset,
        parent: getParentSymbol(def),
      });
    }
  }
  
  return result;
}

// Get top-level symbols only (functions, types)
export function getTopLevelSymbols(symbols: SymbolTable): DocumentSymbolInfo[] {
  const result: DocumentSymbolInfo[] = [];
  
  for (const def of symbols.getAllDefinitions()) {
    if (def.id.kind === "function" || def.id.kind === "type") {
      // Only include if it's a direct top-level symbol (no dot in qualifiedName)
      if (!def.id.qualifiedName.includes(".")) {
        result.push({
          name: def.name,
          kind: def.id.kind,
          loc: def.loc,
          nameOffset: def.nameOffset,
        });
      }
    }
  }
  
  return result;
}

function shouldIncludeInOutline(def: SymbolDef): boolean {
  const kind = def.id.kind;
  const qn = def.id.qualifiedName;
  
  // Always include top-level functions and types
  if ((kind === "function" || kind === "type") && !qn.includes(".")) {
    return true;
  }
  
  // Include fields and methods (they're direct children of types)
  if (kind === "field" || kind === "method") {
    return true;
  }
  
  // Skip local variables and parameters for outline
  return false;
}

function getParentSymbol(def: SymbolDef): string | undefined {
  if (def.id.kind === "field" || def.id.kind === "method") {
    // Extract parent type name from qualified name (TypeName.memberName)
    const parts = def.id.qualifiedName.split(".");
    if (parts.length >= 2) {
      return parts[0];
    }
  }
  return undefined;
}
