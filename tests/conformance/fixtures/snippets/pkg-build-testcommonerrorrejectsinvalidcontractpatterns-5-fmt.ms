# conform: tags=formatter,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:85 TestCommonErrorRejectsInvalidContractPatterns
def wrong(values: List[JsonError]) -> List[Error]:
    return values
