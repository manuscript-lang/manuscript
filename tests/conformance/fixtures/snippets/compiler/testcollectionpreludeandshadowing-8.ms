// conform: tags=diagnostics,maps,strings,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:70 TestCollectionPreludeAndShadowing
fn f(m Map[String, Int]) Void {
	m.add("a", true)
}
// expect-error: MS3001 5:16 expected Int, found Bool (in argument 'value' of m.add)
