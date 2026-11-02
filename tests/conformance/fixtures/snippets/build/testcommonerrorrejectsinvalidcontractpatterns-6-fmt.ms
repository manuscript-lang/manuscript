# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:88 TestCommonErrorRejectsInvalidContractPatterns
fn wrong(operation: fn() JsonError) fn() Error:
    return operation
