# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:82 TestCommonErrorRejectsInvalidContractPatterns
fn wrong(value: Error) JsonError:
    return value
