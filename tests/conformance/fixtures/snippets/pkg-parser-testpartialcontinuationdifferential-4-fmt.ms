# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_continuation_test.go:94 TestPartialContinuationDifferential
export def later[T](value: T) -> T:
    return value
