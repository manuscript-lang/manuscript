// conform: tags=diagnostics,lists,sets,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:77 TestCollectionPreludeAndShadowing
fn f(values Set[List[Int]]) Void {
	return
}
// expect-error: MS3021 4:13 List[Int] does not satisfy Hashable; collections have no Hashable implementation, so use a type as the key or join the elements into a String
