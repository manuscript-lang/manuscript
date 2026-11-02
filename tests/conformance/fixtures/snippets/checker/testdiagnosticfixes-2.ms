# conform: tags=control-flow,diagnostics,interfaces,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:22 TestDiagnosticFixes
interface Named:
    fn name() String

impl Named for Result[Int]:
    fn name() String:
        return "x"

fn f(x: Result[Int]) Int!:
    return error(x)
