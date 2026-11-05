// conform: tags=alternatives,diagnostics,match,records,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/collection_prelude_imports_test.go:84 TestCollectionSupportShadowingAndCaseLookup
enum Other:
    OutOfRange

fn other() Other: Other.OutOfRange

fn standard() Error: Error("collection: out of range", kind: "ERANGE")

fn recognize(value: Other) Int:
    match value:
        OutOfRange: return 1
