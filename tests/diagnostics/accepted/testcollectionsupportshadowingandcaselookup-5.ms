// conform: tags=alternatives,diagnostics,formatter,lists,records,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/collection_prelude_imports_test.go:110 TestCollectionSupportShadowingAndCaseLookup
enum CollectionError {
	OutOfRange
}

fn get() List[Int]! => [1].slice(0, 1)
// expect-exit: 0
