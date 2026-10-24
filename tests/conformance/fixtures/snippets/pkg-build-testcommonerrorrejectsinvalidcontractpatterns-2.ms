# conform: tags=diagnostics,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:74 TestCommonErrorRejectsInvalidContractPatterns
type Impostor:
    detail: String

def wrong(value: Impostor) -> Error:
    return value
