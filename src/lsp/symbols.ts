// Symbol Table for LSP features
import type { SourceLocation } from "../parser/ast";

export interface SymbolId {
  kind: "function" | "type" | "field" | "method" | "variable" | "parameter" | "import";
  qualifiedName: string;
}

export interface SymbolDef {
  id: SymbolId;
  name: string;
  loc: SourceLocation;
  nameOffset: number;
  /** When id.kind === "import", points to the defining module and exported name for go-to-def/hover */
  importTarget?: { specifier: string; exportedName: string };
}

export interface SymbolRef {
  symbolId: SymbolId;
  loc: SourceLocation;
}

export function isSymbolDef(sym: SymbolDef | SymbolRef): sym is SymbolDef {
  return "nameOffset" in sym;
}

export class SymbolTable {
  private definitions = new Map<string, SymbolDef>();
  private references: SymbolRef[] = [];

  addDefinition(def: SymbolDef): void {
    this.definitions.set(def.id.qualifiedName, def);
  }

  addReference(ref: SymbolRef): void {
    this.references.push(ref);
  }

  getDefinition(qualifiedName: string): SymbolDef | undefined {
    return this.definitions.get(qualifiedName);
  }

  getDefinitionById(id: SymbolId): SymbolDef | undefined {
    return this.definitions.get(id.qualifiedName);
  }

  findMember(typeName: string, memberName: string): SymbolDef | undefined {
    return this.definitions.get(`${typeName}.${memberName}`);
  }

  getReferences(qualifiedName: string): SymbolRef[] {
    return this.references.filter(r => r.symbolId.qualifiedName === qualifiedName);
  }

  getAllDefinitions(): SymbolDef[] {
    return Array.from(this.definitions.values());
  }

  getAllReferences(): SymbolRef[] {
    return this.references;
  }
}
