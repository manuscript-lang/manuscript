// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/mutation_test.go:28 TestMutationRejections
fn f(value Val) Void:
    value = Val(val: 1)
