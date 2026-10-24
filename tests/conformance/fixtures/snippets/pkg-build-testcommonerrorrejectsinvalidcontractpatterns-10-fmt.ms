# conform: tags=formatter,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:111 TestCommonErrorRejectsInvalidContractPatterns
def wrong(cause: Error) -> String:
    match cause:
        case JsonError.InvalidData(value):
            return "invalid"
        case _:
            return cause.message()
