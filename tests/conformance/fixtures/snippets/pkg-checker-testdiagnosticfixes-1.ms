# conform: tags=control-flow,diagnostics,interfaces,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:21 TestDiagnosticFixes
impl Error for Result:
    fn message() String:
        return "x"
fn general(value: Result) Error:
    return value
