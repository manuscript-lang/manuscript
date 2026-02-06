// LSP Support - Language Server Protocol utilities
export { SymbolTable, type SymbolDef, type SymbolRef, type SymbolId } from "./symbols";
export { buildSymbolTable } from "./symbol-builder";
export {
  resolveSymbolAt,
  resolveDefinition,
  findReferences,
  getRenameLocations,
  type RenameLocation,
} from "./resolver";
export { getHoverForSymbol, type HoverInfo } from "./hover";
export { getDocumentSymbols, getTopLevelSymbols, type DocumentSymbolInfo, type DocumentSymbolKind } from "./document-symbols";
export {
  getTypeMemberCompletions,
  getObjectMemberCompletions,
  getInterfaceMemberCompletions,
  getScopeCompletions,
  getTypeAnnotationCompletions,
  getDefaultCompletions,
  type CompletionInfo,
  type CompletionKind,
} from "./completions";
export {
  resolveStdlibDefinition,
  getStdlibHover,
  type StdlibDefinitionLocation,
} from "./stdlib";