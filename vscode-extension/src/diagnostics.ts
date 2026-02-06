import * as path from "path";
import { Diagnostic, DiagnosticSeverity } from "vscode-languageserver/node";
import type { CompileError, CompileWarning } from "../../src/cli/compiler";

const SOURCE = "manuscript";
const ERROR_SUFFIX = / at line \d+, column \d+$/;

function errorToDiagnostic(err: CompileError): Diagnostic {
  const line = (err.line ?? 1) - 1;
  const col = (err.column ?? 1) - 1;
  return {
    severity: DiagnosticSeverity.Error,
    range: {
      start: { line, character: col },
      end: { line, character: col + 10 },
    },
    message: err.message.replace(ERROR_SUFFIX, ""),
    source: SOURCE,
  };
}

function warningToDiagnostic(_w: CompileWarning): Diagnostic {
  return {
    severity: DiagnosticSeverity.Warning,
    range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
    message: _w.message,
    source: SOURCE,
  };
}

export function errorsToDiagnostics(
  errors: CompileError[],
  entryPath?: string
): Diagnostic[] {
  const entryAbs = entryPath ? path.resolve(entryPath) : undefined;
  return errors
    .filter((err) => !entryAbs || (err.file && path.resolve(err.file) === entryAbs))
    .map(errorToDiagnostic);
}

export function warningsToDiagnostics(
  warnings: CompileWarning[],
  entryPath?: string
): Diagnostic[] {
  const entryAbs = entryPath ? path.resolve(entryPath) : undefined;
  return warnings
    .filter((w) => !entryAbs || (w.file && path.resolve(w.file) === entryAbs))
    .map(warningToDiagnostic);
}
