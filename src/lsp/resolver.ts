// Symbol Resolver - High-level API for LSP features
import type { SymbolTable, SymbolDef, SymbolRef } from "./symbols";
import { isSymbolDef } from "./symbols";
import { isLocationMatch } from "./utils";

export interface ResolvedSymbol {
  definition: SymbolDef;
  references: SymbolRef[];
}

// Simple location for LSP (doesn't need offset)
export interface RenameLocation {
  loc: { line: number; column: number };
  length: number;
}

// Find the symbol at a given position
export function resolveSymbolAt(
  symbols: SymbolTable,
  line: number,
  column: number
): SymbolDef | SymbolRef | undefined {
  // Check definitions first
  for (const def of symbols.getAllDefinitions()) {
    if (isLocationMatch(def.loc, def.nameOffset, def.name.length, line, column)) {
      return def;
    }
  }
  // Check references
  for (const ref of symbols.getAllReferences()) {
    const def = symbols.getDefinitionById(ref.symbolId);
    if (def && isLocationMatch(ref.loc, 0, def.name.length, line, column)) {
      return ref;
    }
  }
  return undefined;
}

// Get the definition for a symbol (works for both definitions and references)
export function resolveDefinition(
  symbols: SymbolTable,
  line: number,
  column: number
): SymbolDef | undefined {
  const symbol = resolveSymbolAt(symbols, line, column);
  if (!symbol) return undefined;
  if (isSymbolDef(symbol)) return symbol;
  return symbols.getDefinitionById(symbol.symbolId);
}

// Find all references to the symbol at a given position
export function findReferences(
  symbols: SymbolTable,
  line: number,
  column: number
): { definition: SymbolDef; references: SymbolRef[] } | undefined {
  const def = resolveDefinition(symbols, line, column);
  if (!def) return undefined;
  
  const refs = symbols.getReferences(def.id.qualifiedName);
  return { definition: def, references: refs };
}

// Get all locations for renaming a symbol (definition + all references)
export function getRenameLocations(
  symbols: SymbolTable,
  line: number,
  column: number
): RenameLocation[] | undefined {
  const result = findReferences(symbols, line, column);
  if (!result) return undefined;

  const locations: RenameLocation[] = [];
  const { definition, references } = result;

  // Add definition location (with nameOffset adjustment)
  locations.push({
    loc: {
      line: definition.loc.line,
      column: definition.loc.column + definition.nameOffset,
    },
    length: definition.name.length,
  });

  // Add all reference locations
  for (const ref of references) {
    locations.push({ loc: ref.loc, length: definition.name.length });
  }

  return locations;
}
