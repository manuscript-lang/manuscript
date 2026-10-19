# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:88 TestCommonErrorRejectsInvalidContractPatterns
fn wrong(operation: fn() JsonError) fn() Error:
    return operation
