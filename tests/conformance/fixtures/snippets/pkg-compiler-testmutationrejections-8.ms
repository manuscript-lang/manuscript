# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:29 TestMutationRejections
fn f() Unit:
    let value = 1
    value += 1
