# conform: tags=control-flow,formatter,interfaces,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:22 TestDiagnosticFixes
impl Error for Result[Int]:
    fn message() String:
        return "x"

fn f(x: Result[Int]) Result[Int, Error]:
    return error(x)
