// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/standard_test.go:29 TestDiskStandardDeclarationsUseOrdinarySyntax
fn missing_binding() Int { ... }
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
