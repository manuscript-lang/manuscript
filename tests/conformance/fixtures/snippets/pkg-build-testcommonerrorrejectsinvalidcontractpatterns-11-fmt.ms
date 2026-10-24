# conform: tags=formatter,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:118 TestCommonErrorRejectsInvalidContractPatterns
def wrong(cause: Error) -> String:
    match cause:
        case JsonError:
            return "invalid"
        case _:
            return cause.message()
