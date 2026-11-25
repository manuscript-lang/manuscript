// conform: tags=diagnostics,formatter,sets,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:76 TestCollectionPreludeAndShadowing
fn f(values Set[Int]) Void {
	values.add(true)
}
// expect-error: MS3001 5:16 expected Int, found Bool (in argument 'value' of values.add)
