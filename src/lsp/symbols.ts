// Symbol Table for LSP features
import type { SourceLocation } from "../parser/ast";

export interface SymbolId {
  kind: "function" | "type" | "field" | "method" | "variable" | "parameter";
  // Fully qualified name: "fn_name", "TypeName", "TypeName.member"
  qualifiedName: string;
}

export interface SymbolDef {
  id: SymbolId;
  name: string;
  loc: SourceLocation;
  // Name offset within the declaration (e.g., 3 for "fn " prefix)
  nameOffset: number;
}

export interface SymbolRef {
  symbolId: SymbolId;
  loc: SourceLocation;
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
