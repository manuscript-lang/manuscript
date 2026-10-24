# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:30 TestMutationRejections
def f(value: Int) -> Unit:
    value -= 1
