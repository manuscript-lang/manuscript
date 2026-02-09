import type * as AST from "../parser/ast";
import type { Type } from "./types";
import type { TypeEnvironment } from "./environment";
import { PassManager } from "./pass-manager";
import { getModuleExports } from "./module-exports";
import { toDiagnostic, warningToDiagnostic, type Diagnostic } from "../shared/diagnostics";
import type { GetStdlibErrorsFn } from "./checker";

export interface RunProjectTypecheckOptions {
  typeCheck?: boolean;
  entryAbs?: string;
  /** Normalize path for map keys and entry comparison; default identity. */
  resolvePath?: (p: string) => string;
  getStdlibErrors?: GetStdlibErrorsFn;
}

export interface RunProjectTypecheckResult {
  moduleExportsMap: Map<string, Map<string, Type>>;
  errors: Diagnostic[];
  warnings: Diagnostic[];
  entryProgram?: AST.Program;
  entryEnv?: TypeEnvironment;
}

export type GetInitialEnvResult = { env: TypeEnvironment; errors?: Diagnostic[] };

export function runProjectTypecheck(
  order: string[],
  getProgram: (filePath: string) => AST.Program,
  getInitialEnv: (filePath: string, moduleExportsMap: Map<string, Map<string, Type>>) => GetInitialEnvResult,
  options: RunProjectTypecheckOptions = {}
): RunProjectTypecheckResult {
  const { typeCheck = true, entryAbs, resolvePath = (p: string) => p, getStdlibErrors } = options;
  const moduleExportsMap = new Map<string, Map<string, Type>>();
  const errors: Diagnostic[] = [];
  const warnings: Diagnostic[] = [];
  const passManager = PassManager.createDefault();
  let entryProgram: AST.Program | undefined;
  let entryEnv: TypeEnvironment | undefined;

  for (const filePath of order) {
    const program = getProgram(filePath);
    const { env, errors: importErrors } = getInitialEnv(filePath, moduleExportsMap);
    if (importErrors?.length) errors.push(...importErrors);

    if (getStdlibErrors) {
      for (const te of getStdlibErrors(program, env)) errors.push(toDiagnostic(te, filePath));
    }

    const result = passManager.runWithEnv(program, env);
    if (typeCheck) {
      for (const te of result.errors) errors.push(toDiagnostic(te, filePath));
      for (const w of result.warnings) warnings.push(warningToDiagnostic(w, filePath));
    }

    const exportResult = getModuleExports(program, result.env);
    for (const e of exportResult.errors) errors.push(toDiagnostic({ message: e.message, loc: e.loc }, filePath));
    moduleExportsMap.set(resolvePath(filePath), exportResult.exports);

    if (entryAbs && resolvePath(filePath) === entryAbs) {
      entryProgram = program;
      entryEnv = result.env;
    }
  }

  return { moduleExportsMap, errors, warnings, entryProgram, entryEnv };
}
