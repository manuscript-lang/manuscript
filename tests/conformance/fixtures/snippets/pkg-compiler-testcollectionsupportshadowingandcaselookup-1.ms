# conform: tags=alternatives,diagnostics,match,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:84 TestCollectionSupportShadowingAndCaseLookup
type Other:
    case OutOfRange

fn other() Other: Other.OutOfRange

fn standard() CollectionError: CollectionError.OutOfRange

fn recognize(value: Other) Int:
    match value:
        OutOfRange: return 1
