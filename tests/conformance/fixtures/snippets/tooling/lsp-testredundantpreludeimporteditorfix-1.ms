// conform: tags=diagnostics,lists,modules,stdlib-errors,tier-stdlib,try-result
// conform: phase=check
// conform: origin=pkg/tooling/lsp/prelude_imports_test.go:43 TestRedundantPreludeImportEditorFix
import Error from "@std/core.ms"  // keep

fn first(values List[Int]) Int! => ok_or(values.first(), Error("missing"))
