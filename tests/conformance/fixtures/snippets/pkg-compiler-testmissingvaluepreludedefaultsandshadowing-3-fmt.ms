# conform: tags=alternatives,formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:203 TestMissingValuePreludeDefaultsAndShadowing
type Other:
    case Missing(value: Int)

def get() -> Other: Missing(1)
