# conform: tags=diagnostics,match,strings,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:118 TestCommonErrorRejectsInvalidContractPatterns
fn wrong(cause: Error) String:
    match cause:
        JsonError:
            return "invalid"
        _:
            return cause.message()
