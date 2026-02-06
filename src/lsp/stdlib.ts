// LSP helpers for stdlib imports (hover, go-to-definition, find refs).
// Uses typechecking pipeline (getStdlibTypes) and loader (export location, URI) only; no AST in LSP.

import {
  isStdlibImport,
  stdlibModuleName,
  getStdlibTypes,
  getStdlibModuleUri,
  getStdlibExportLocation,
} from "../stdlib/loader";
import { getHoverForType, type HoverInfo } from "./hover";

export { isStdlibImport };

export interface StdlibDefinitionLocation {
  uri: string;
  range: { start: { line: number; character: number }; end: { line: number; character: number } };
}

export function resolveStdlibDefinition(
  specifier: string,
  exportedName: string
): StdlibDefinitionLocation | null {
  if (!isStdlibImport(specifier)) return null;
  const moduleName = stdlibModuleName(specifier);
  const decl = getStdlibExportLocation(moduleName, exportedName);
  if (!decl) return null;
  const uri = getStdlibModuleUri(moduleName);
  const line0 = decl.loc.line - 1;
  const col = decl.loc.column - 1 + decl.nameOffset;
  return {
    uri,
    range: {
      start: { line: line0, character: col },
      end: { line: line0, character: col + decl.name.length },
    },
  };
}

export function getStdlibHover(specifier: string, exportedName: string): HoverInfo | null {
  if (!isStdlibImport(specifier)) return null;
  const moduleName = stdlibModuleName(specifier);
  const stdTypes = getStdlibTypes(moduleName);
  if (!stdTypes) return null;
  const type = stdTypes.functions.get(exportedName) ?? stdTypes.types.get(exportedName);
  if (!type) return null;
  return getHoverForType(exportedName, type);
}
