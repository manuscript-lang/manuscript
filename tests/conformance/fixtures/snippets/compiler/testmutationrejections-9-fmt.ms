# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:30 TestMutationRejections
fn f(value: Int) Unit:
    value -= 1
