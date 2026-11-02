# conform: tags=closures,diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/contextual_generics_test.go:45 TestExpectedResultGenericInference
fn first() Unit:
    let callback: fn() Int? = fn: absent()
