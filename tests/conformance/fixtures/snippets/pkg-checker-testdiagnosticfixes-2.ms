# conform: tags=control-flow,diagnostics,interfaces,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:22 TestDiagnosticFixes
impl Error for Result[Int]:
    def message() -> String:
        return "x"

def f(x: Result[Int]) -> Result[Int, Error]:
    return error(x)
