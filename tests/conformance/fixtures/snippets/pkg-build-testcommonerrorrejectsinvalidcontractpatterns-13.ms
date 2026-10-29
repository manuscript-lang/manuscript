# conform: tags=diagnostics,match,strings,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:134 TestCommonErrorRejectsInvalidContractPatterns
fn wrong(cause: Error) String:
    match cause:
        JsonError(first):
            return first.message()
        JsonError(second):
            return second.message()
        _:
            return cause.message()
