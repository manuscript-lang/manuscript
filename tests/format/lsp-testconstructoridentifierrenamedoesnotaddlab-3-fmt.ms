// conform: tags=alternatives,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/lsp/positional_arguments_test.go:57 TestConstructorIdentifierRenameDoesNotAddLabels
enum Pair {
	Values(first Int, second Int)
}
// expect-format: rewritten
// expect-formatted: enum Pair {
// expect-formatted: \tValues(first, second Int)
// expect-formatted: }
