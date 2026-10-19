# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:82 TestCommonErrorRejectsInvalidContractPatterns
fn wrong(value: Error) JsonError:
    return value
