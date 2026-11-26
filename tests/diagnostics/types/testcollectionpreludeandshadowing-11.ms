// conform: tags=diagnostics,formatter,maps,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:73 TestCollectionPreludeAndShadowing
fn f(m Map[Int, Int]) Void {
	m.add(1)
}
// expect-error: MS3003 5:7 missing argument value: Int in call to m.add; add 'value: <Int>'
