# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/default_type_arguments_test.go:23 TestDefaultTypeArgumentRules
type Pair[A, B = A]:
    first: A
    second: B

def use() -> Pair[Int]: Pair[Int](1, 2)
