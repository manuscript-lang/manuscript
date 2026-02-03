// LSP Support - Language Server Protocol utilities
export { SymbolTable, type SymbolDef, type SymbolRef, type SymbolId } from "./symbols";
export { buildSymbolTable } from "./symbol-builder";
export {
  resolveSymbolAt,
  resolveDefinition,
  findReferences,
  getRenameLocations,
  canRename,
  type RenameLocation,
} from "./resolver";
export { getHoverForSymbol, type HoverInfo } from "./hover";
export { getDocumentSymbols, getTopLevelSymbols, type DocumentSymbolInfo, type DocumentSymbolKind } from "./document-symbols";
export {
  getTypeMemberCompletions,
  getObjectMemberCompletions,
  getScopeCompletions,
  resolveObjectType,
  type CompletionInfo,
  type CompletionKind,
} from "./completions";

// Re-export utilities that may be useful
export {
  formatAstType,
  formatFnSignature,
  formatTypeSignature,
  getDocstring,
  findFnDecl,
  findTypeDecl,
} from "./utils";
