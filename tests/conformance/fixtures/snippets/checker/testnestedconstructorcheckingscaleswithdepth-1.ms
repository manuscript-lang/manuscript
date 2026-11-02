# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/nested_literal_test.go:107 TestNestedConstructorCheckingScalesWithDepth
type Box[T]:
    value: T
