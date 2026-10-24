# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:88 TestCommonErrorRejectsInvalidContractPatterns
def wrong(operation: Callable[[], JsonError]) -> Callable[[], Error]:
    return operation
