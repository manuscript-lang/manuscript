# conform: tags=formatter,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:118 TestCommonErrorRejectsInvalidContractPatterns
fn wrong(cause: Error) String:
    match cause:
        JsonError:
            return "invalid"
        _:
            return cause.message()
