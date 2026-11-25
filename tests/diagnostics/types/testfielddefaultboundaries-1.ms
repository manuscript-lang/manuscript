// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/field_defaults_test.go:11 TestFieldDefaultBoundaries
type Options {
	count Int = true
}
// expect-error: MS3001 5:17 expected Int, found Bool
