// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/index_tokens_test.go:43 TestPinnedIndexTokensRequireExactInput
export fn different() Int {
	return 9
}
// expect-exit: 0
