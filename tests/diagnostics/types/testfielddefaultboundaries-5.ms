// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/field_defaults_test.go:15 TestFieldDefaultBoundaries
type Box[T] {
	value T = 1
}
// expect-error: MS3001 5:15 expected T, found Int
