# conform: tags=diagnostics,generics,lists,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:109 TestCollectionSupportShadowingAndCaseLookup
type ListEntry[T]:
    payload: T

def get() -> List[ListEntry[Int]]: [1].entries()
