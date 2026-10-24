# conform: tags=alternatives,diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:108 TestCollectionSupportShadowingAndCaseLookup
type Other:
    case OutOfRange

def get() -> Other: OutOfRange
