# conform: tags=diagnostics,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/build/library_test.go:79 TestCommonErrorRejectsInvalidContractPatterns
fn wrong() String!:
    return Result[Int, Error].ok(value: 1)
