// conform: tags=diagnostics,lists,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/tooling/lsp/prelude_imports_test.go:89 TestMissingValuePreludeNavigation
fn first(values: List[Int]) Int!: ok_or(values.first(), Error("missing"))
