# conform: tags=diagnostics,match,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:125 TestCommonErrorRejectsInvalidContractPatterns
type Other:
    detail: String

def wrong(cause: Error) -> String:
    match cause:
        case Other(value):
            return value.detail
        case _:
            return cause.message()
