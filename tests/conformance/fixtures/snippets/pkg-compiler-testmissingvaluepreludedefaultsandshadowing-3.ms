# conform: tags=alternatives,diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:203 TestMissingValuePreludeDefaultsAndShadowing
type Other:
    case Missing(value: Int)
fn get() Other: Missing(1)
