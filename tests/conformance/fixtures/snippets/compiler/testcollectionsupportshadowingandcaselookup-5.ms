// conform: tags=alternatives,diagnostics,lists,records,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/collection_prelude_imports_test.go:110 TestCollectionSupportShadowingAndCaseLookup
enum CollectionError:
    case OutOfRange

fn get() List[Int]!: [1].slice(0, 1)
