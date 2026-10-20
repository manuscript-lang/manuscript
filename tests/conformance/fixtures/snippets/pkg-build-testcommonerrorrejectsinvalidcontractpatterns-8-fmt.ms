# conform: tags=formatter,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:101 TestCommonErrorRejectsInvalidContractPatterns
type Impostor:
    detail: String
fn wrong(value: Impostor) Error:
    return Error(value: value)
