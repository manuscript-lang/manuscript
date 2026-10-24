# conform: tags=control-flow,diagnostics,interfaces,numbers,records,sets,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:27 TestDiagnosticFixes
type K:
    v: Float

impl Equal for K:
    def equals(other: Equal) -> Bool:
        return True

def f() -> Int:
    let s = Set[K]()
    return 0
