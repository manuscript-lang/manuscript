# conform: tags=formatter,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:106 TestCommonErrorRejectsInvalidContractPatterns
def wrong(cause: Error) -> String:
    match cause:
        case JsonError(value):
            return value.message()
