// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/nested_literal_test.go:107 TestNestedConstructorCheckingScalesWithDepth
type Box[T] {
	value T
}
// expect-exit: 0
