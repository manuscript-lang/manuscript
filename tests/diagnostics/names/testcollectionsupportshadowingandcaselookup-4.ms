// conform: tags=diagnostics,formatter,generics,lists,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/collection_prelude_imports_test.go:109 TestCollectionSupportShadowingAndCaseLookup
type ListEntry[T] {
	payload T
}

fn get() List[ListEntry[Int]] => [1].entries()
// expect-error: MS2001 4:1 declaration ListEntry reuses a prelude name; rename it, because ListEntry always refers to the standard declaration
