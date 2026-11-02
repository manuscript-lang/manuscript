# conform: tags=formatter,lists,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:43 TestRedundantPreludeImportEditorFix
import Error from "@std/core.ms"  # keep

fn first(values: List[Int]) Int!: values.first().ok_or()
