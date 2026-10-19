# conform: tags=formatter,lists,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:43 TestRedundantPreludeImportEditorFix
import MissingValue from "@std/errors.ms" # keep
fn first(values: List[Int]) Result[Int, MissingValue]: values.first().ok_or()
