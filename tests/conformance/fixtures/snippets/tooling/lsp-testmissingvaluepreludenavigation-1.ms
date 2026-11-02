# conform: tags=diagnostics,lists,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:89 TestMissingValuePreludeNavigation
fn first(values: List[Int]) Int!MissingValue: values.first().ok_or()
