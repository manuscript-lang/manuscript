# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:27 TestMutationRejections
def f() -> Unit:
    let value = Val(val: 0)
    value = Val(val: 1)
