# conform: tags=alternatives,diagnostics,match,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:187 TestMissingValuePreludeDefaultsAndShadowing
type Other:
    case Missing(value: Int)

def other() -> Other: Other.Missing(1)

def standard() -> MissingValue: MissingValue.Missing("location")

def read(value: Other) -> Int:
    match value:
        case Missing(found): return found
