# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:23 TestMutationRejections
def f(value: Val) -> Unit:
    value.val = True
