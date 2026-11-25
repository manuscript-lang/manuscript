// conform: tags=diagnostics,formatter,modules,stdlib-|,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/prelude_imports_test.go:141 TestPreludeImportCompletionSpacingAndRecovery
import Name from "@std/|"
// expect-error: MS2002 4:8-4:12 unknown standard module @std/|
