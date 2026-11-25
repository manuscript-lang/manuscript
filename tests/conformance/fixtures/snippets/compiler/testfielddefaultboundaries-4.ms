// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/field_defaults_test.go:14 TestFieldDefaultBoundaries
type Options {
	required Int
	count Int = 1
}

fn f() Options => return Options()
// expect-error: MS3003 9:26 missing argument required: Int in call to Options; add 'required: <Int>'
