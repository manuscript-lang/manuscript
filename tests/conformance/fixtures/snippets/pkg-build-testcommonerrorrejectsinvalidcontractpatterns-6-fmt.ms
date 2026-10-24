# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:88 TestCommonErrorRejectsInvalidContractPatterns
def wrong(operation: Callable[[], JsonError]) -> Callable[[], Error]:
    return operation
