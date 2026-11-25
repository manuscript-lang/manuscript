// conform: tags=diagnostics,formatter,lists,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/collection_prelude_imports_test.go:111 TestCollectionSupportShadowingAndCaseLookup
fn entries(values MapEntry[List[Int], Int]) Void => void
// expect-error: MS3021 4:19 List[Int] does not satisfy Hashable; collections have no Hashable implementation, so use a type as the key or join the elements into a String
