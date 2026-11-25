// conform: tags=diagnostics,formatter,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/position_consumers_test.go:23 TestSemanticOriginalUnicodeAndRecoveryPositions
// α😀
fn answer() String => "é😀"
// expect-exit: 0
