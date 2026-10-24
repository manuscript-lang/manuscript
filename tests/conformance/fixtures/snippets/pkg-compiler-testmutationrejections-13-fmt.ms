# conform: tags=aliasing,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:34 TestMutationRejections
def f() -> Unit:
    stdout().clone()
