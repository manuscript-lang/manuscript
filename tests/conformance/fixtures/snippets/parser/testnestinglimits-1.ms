// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/nesting_test.go:12 TestNestingLimits
fn f() Int {
	return
}
// expect-error: MS3000 5:5 bare return requires Void or Void!; this function returns Int, so write 'return <value>'
