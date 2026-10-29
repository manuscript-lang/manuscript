# conform: tags=closures,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/contextual_generics_test.go:45 TestExpectedResultGenericInference
fn first() Unit:
    let callback: fn() Optional[Int] = fn: absent()
