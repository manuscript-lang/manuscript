# conform: tags=formatter,match,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:125 TestCommonErrorRejectsInvalidContractPatterns
type Other:
    detail: String

fn wrong(cause: Error) String:
    match cause:
        Other(value):
            return value.detail
        _:
            return cause.message()
