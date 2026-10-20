# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:32 TestDiagnosticFixes
interface I:
    fn n() Int
type Pair[A, B]:
    a: A
    b: B
impl I for Pair[A, A]:
    fn n() Int:
        return 1
export fn main() Int:
    return I(value: Pair[Int, String](a: 1, b: "x")).n()
