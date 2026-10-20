# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/default_type_arguments_test.go:23 TestDefaultTypeArgumentRules
type Pair[A, B = A]:
    first: A
    second: B
fn use() Pair[Int]: Pair[Int](1, 2)
