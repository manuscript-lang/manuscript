# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/nested_literal_test.go:107 TestNestedConstructorCheckingScalesWithDepth
type Box[T]:
    value: T
