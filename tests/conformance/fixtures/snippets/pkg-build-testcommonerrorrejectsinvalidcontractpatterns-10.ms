# conform: tags=diagnostics,match,strings,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:111 TestCommonErrorRejectsInvalidContractPatterns
def wrong(cause: Error) -> String:
    match cause:
        case JsonError.InvalidData(value):
            return "invalid"
        case _:
            return cause.message()
