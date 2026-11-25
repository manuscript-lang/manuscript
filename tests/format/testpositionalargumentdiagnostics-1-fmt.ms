// conform: tags=formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/positional_arguments_test.go:66 TestPositionalArgumentDiagnostics
type Pair {
	first Int
	second Int
}
// expect-format: rewritten
// expect-formatted: type Pair {
// expect-formatted: \tfirst, second Int
// expect-formatted: }
