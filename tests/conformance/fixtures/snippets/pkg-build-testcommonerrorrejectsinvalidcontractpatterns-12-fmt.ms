# conform: tags=formatter,match,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:125 TestCommonErrorRejectsInvalidContractPatterns
type Other:
    detail: String

def wrong(cause: Error) -> String:
    match cause:
        case Other(value):
            return value.detail
        case _:
            return cause.message()
