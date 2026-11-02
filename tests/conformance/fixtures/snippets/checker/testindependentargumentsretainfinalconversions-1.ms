# conform: tags=control-flow,diagnostics,generics,interfaces,optional,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/argument_reuse_test.go:12 TestIndependentArgumentsRetainFinalConversions
fn identity[T](value: T) T: value

fn consume[T](value: T, cause: Error, optional: T?) Unit: return

fn first() Unit: consume(value: 1, cause: identity(Error("two")), optional: identity(3))
