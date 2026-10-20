# conform: tags=diagnostics,lists,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:85 TestCommonErrorRejectsInvalidContractPatterns
fn wrong(values: List[JsonError]) List[Error]:
    return values
