// conform: tags=diagnostics,formatter,lists,maps,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:71 TestCollectionPreludeAndShadowing
fn f(m Map[List[Int], Int]) Void {
	return
}
// expect-error: MS3021 4:8 List[Int] does not satisfy Hashable; collections have no Hashable implementation, so use a type as the key or join the elements into a String
