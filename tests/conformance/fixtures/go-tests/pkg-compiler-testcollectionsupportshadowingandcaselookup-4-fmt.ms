# conform: tags=formatter,generics,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:109 TestCollectionSupportShadowingAndCaseLookup
type ListEntry[T]:
    payload: T
fn get() List[ListEntry[Int]]: [1].entries()
