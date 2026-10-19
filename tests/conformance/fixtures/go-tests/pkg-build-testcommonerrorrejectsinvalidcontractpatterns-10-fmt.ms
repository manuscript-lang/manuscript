# conform: tags=formatter,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:111 TestCommonErrorRejectsInvalidContractPatterns
fn wrong(cause: Error) String:
    match cause:
        JsonError.InvalidData(value):
            return "invalid"
        _:
            return cause.message()
