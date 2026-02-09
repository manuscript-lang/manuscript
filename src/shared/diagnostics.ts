export type DiagnosticPhase = "lexer" | "parser" | "typecheck" | "codegen";
export type DiagnosticSeverity = "error" | "warning";

export interface Diagnostic {
  message: string;
  hint?: string;
  line?: number;
  column?: number;
  file?: string;
  phase: DiagnosticPhase;
  severity?: DiagnosticSeverity;
}

/** Shared by compile and types. */
export function toDiagnostic(
  d: { message: string; hint?: string; loc?: { line?: number; column?: number } },
  filePath: string,
  severity: DiagnosticSeverity = "error"
): Diagnostic {
  return {
    message: d.message,
    hint: d.hint,
    line: d.loc?.line,
    column: d.loc?.column,
    file: filePath,
    phase: "typecheck",
    severity,
  };
}

export function warningToDiagnostic(message: string, filePath: string): Diagnostic {
  return toDiagnostic({ message }, filePath, "warning");
}

export function formatErrors(diagnostics: Diagnostic[], source?: string): string {
  const lines = source?.split("\n") ?? [];
  return diagnostics
    .map((d) => {
      let msg = `[${d.phase}] ${d.message}`;
      if (d.file) msg = `${d.file}: ${msg}`;
      if (d.line !== undefined) {
        msg += `\n  at line ${d.line}`;
        if (d.column !== undefined) msg += `, column ${d.column}`;
        if (lines[d.line - 1]) {
          const line = lines[d.line - 1]!;
          msg += `\n\n  ${d.line} | ${line}`;
          if (d.column !== undefined) {
            const padding = " ".repeat(String(d.line).length + 3 + d.column - 1);
            msg += `\n  ${padding}^`;
          }
        }
      }
      if (d.hint) msg += `\n\n  Hint: ${d.hint}`;
      return msg;
    })
    .join("\n\n");
}
