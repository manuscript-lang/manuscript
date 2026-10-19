# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/default_type_arguments_test.go:27 TestDefaultTypeArgumentRules
type Trio[A, B, C = A]:
    first: A
fn use(t: Trio[Int]) Unit: unit
