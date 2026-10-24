# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:28 TestMutationRejections
def f(value: Val) -> Unit:
    value = Val(val: 1)
