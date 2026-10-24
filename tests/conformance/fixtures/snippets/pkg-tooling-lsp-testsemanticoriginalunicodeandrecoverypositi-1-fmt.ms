# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/position_consumers_test.go:23 TestSemanticOriginalUnicodeAndRecoveryPositions
# α😀
def answer() -> String: "é😀"
