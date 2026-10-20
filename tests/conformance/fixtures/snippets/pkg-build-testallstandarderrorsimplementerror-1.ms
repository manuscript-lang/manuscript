# conform: tags=parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:206 TestAllStandardErrorsImplementError
fn diagnostic(cause: %s) String:
    return cause.message()
fn view(cause: %s) Error:
    return cause
