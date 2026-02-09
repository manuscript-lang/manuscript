/** Compile: host from CLI/LSP. Use compileEntry for everything (project or single-file). */
export {
  parseSource,
  compileSingle,
  compile,
  check,
  parse,
  typecheckSingle,
  typecheckDocumentInProject,
  compileEntry,
  checkEntry,
  runCompiledCode,
  runSource,
  runTestsInSource,
  formatErrors,
} from "./compiler";
export type {
  Diagnostic,
  CompileResult,
  CompileOptions,
  ParseResult,
  TypecheckSingleResult,
  ProjectCompileOptions,
  CompileEntryOptions,
  CompileEntryResult,
  MsRuntime,
  RunSourceResult,
  TypecheckDocumentInProjectResult,
} from "./compiler";
