# conform: tags=control-flow,diagnostics,interfaces,numbers,records,sets,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:27 TestDiagnosticFixes
type K:
    v: Float
impl Equal for K:
    fn equals(other: Equal) Bool:
        return true
fn f() Int:
    let s = Set[K]()
    return 0
