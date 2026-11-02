# conform: tags=control-flow,diagnostics,interfaces,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:21 TestDiagnosticFixes
interface Named:
    fn name() String

impl Named for Result:
    fn name() String:
        return "x"

fn general(value: Result) Named:
    return value
