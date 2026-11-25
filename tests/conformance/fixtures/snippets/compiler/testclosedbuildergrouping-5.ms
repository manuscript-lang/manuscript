// conform: tags=diagnostics,modules,stdlib-string,strings,tier-stdlib
// conform: phase=check
// conform: origin=pkg/compiler/builder_range_test.go:30 TestClosedBuilderGrouping

fn fragment() String => return "x"

fn probe(flag Bool) String {
	b := ""
}
// expect-error: MS3000 7:1 reachable fallthrough in function returning String; end every path with 'return <String>' (or make the last branch return)
