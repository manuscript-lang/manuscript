# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:24 TestMutationRejections
def f(value: Val) -> Unit:
    value.missing = 1
