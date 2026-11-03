# conform: tags=alternatives,formatter,lists,parser,records,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:110 TestCollectionSupportShadowingAndCaseLookup
type CollectionError:
    case OutOfRange

fn get() List[Int]!: [1].slice(0, 1)
