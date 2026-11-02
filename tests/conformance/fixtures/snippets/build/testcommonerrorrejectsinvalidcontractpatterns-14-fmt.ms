# conform: tags=formatter,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:143 TestCommonErrorRejectsInvalidContractPatterns
fn wrong(cause: Error) String:
    match cause:
        _:
            return cause.message()
        JsonError(value):
            return value.message()
