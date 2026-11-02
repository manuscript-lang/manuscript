# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:25 TestMutationRejections
fn f() Unit:
    Val.val = 1
