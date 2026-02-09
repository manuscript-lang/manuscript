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
  type CompletionInfo,
  type CompletionKind,
} from "./completions";
export {
  formatFnSignature,
  formatTypeSignature,
  formatInterfaceSignature,
  resolveObjectType,
  resolveInterfaceType,
} from "./format";
export {
  collectTypeMembersFromProgram,
  type BuiltinsSymbol,
  type TypeMemberInfo,
} from "./builtin-symbols";

// LanguageService — high-level API for protocol adapters
export {
  LanguageService,
  type LanguageServiceHost,
  type DiagnosticInfo,
  type DefinitionResult,
  type ReferenceLocation,
  type RenameLocationInfo,
  type CompletionItemData,
} from "./service";
