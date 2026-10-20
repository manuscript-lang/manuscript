# conform: tags=control-flow,formatter,interfaces,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:21 TestDiagnosticFixes
impl Error for Result:
    fn message() String:
        return "x"
fn general(value: Result) Error:
    return value
