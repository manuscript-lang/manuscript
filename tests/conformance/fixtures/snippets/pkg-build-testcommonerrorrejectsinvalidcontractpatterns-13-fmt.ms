# conform: tags=formatter,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:134 TestCommonErrorRejectsInvalidContractPatterns
def wrong(cause: Error) -> String:
    match cause:
        case JsonError(first):
            return first.message()
        case JsonError(second):
            return second.message()
        case _:
            return cause.message()
