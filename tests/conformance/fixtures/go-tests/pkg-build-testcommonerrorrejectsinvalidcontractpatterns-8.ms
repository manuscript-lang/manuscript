# conform: tags=diagnostics,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:101 TestCommonErrorRejectsInvalidContractPatterns
type Impostor:
    detail: String
fn wrong(value: Impostor) Error:
    return Error(value: value)
