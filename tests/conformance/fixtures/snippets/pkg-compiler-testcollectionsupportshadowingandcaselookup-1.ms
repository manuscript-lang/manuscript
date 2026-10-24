# conform: tags=alternatives,diagnostics,match,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:84 TestCollectionSupportShadowingAndCaseLookup
type Other:
    case OutOfRange

def other() -> Other: Other.OutOfRange

def standard() -> CollectionError: CollectionError.OutOfRange

def recognize(value: Other) -> Int:
    match value:
        case OutOfRange: return 1
