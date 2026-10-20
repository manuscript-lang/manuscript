# conform: tags=closures,formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callback_work_test.go:93 TestCallbackProbeRetainsCapturedBindingsAndOptionalMetadata
fn wrap[T](callback: Optional[fn(value: Int) T]) Unit: return
fn apply[T, U](value: T, transform: fn(value: T) U) U: transform(value)
fn first() Unit:
    let offset = 7
    let result = apply(value: 1, transform: fn(outer): apply(value: 2, transform: fn(inner): outer + inner + offset))
    wrap(fn(item: Int = 4): item + offset)
