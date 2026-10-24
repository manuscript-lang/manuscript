# conform: tags=diagnostics,lists,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:43 TestRedundantPreludeImportEditorFix
from "@std/core.ms" import MissingValue  # keep

def first(values: List[Int]) -> Result[Int, MissingValue]: values.first().ok_or()
