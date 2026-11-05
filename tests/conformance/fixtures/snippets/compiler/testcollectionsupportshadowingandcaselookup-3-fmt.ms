// conform: tags=alternatives,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/collection_prelude_imports_test.go:108 TestCollectionSupportShadowingAndCaseLookup
enum Other:
    case OutOfRange

fn get() Other: OutOfRange
