# conform: tags=diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/position_consumers_test.go:23 TestSemanticOriginalUnicodeAndRecoveryPositions
# α😀
fn answer() String: "é😀"
