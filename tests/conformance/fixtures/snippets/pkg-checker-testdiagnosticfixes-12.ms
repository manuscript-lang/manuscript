# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:32 TestDiagnosticFixes
interface I:
    def n() -> Int

type Pair[A, B]:
    a: A
    b: B

impl I for Pair[A, A]:
    def n() -> Int:
        return 1

export def main() -> Int:
    return I(value: Pair[Int, String](a: 1, b: "x")).n()
