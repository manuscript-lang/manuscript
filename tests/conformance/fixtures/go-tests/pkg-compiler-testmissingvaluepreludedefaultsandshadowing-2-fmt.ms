# conform: tags=alternatives,formatter,match,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:187 TestMissingValuePreludeDefaultsAndShadowing
type Other:
    case Missing(value: Int)
fn other() Other: Other.Missing(1)
fn standard() MissingValue: MissingValue.Missing("location")
fn read(value: Other) Int:
    match value:
        Missing(found): return found
