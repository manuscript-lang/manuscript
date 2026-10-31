# conform: tags=closures,diagnostics,generics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/callback_work_test.go:93 TestCallbackProbeRetainsCapturedBindingsAndOptionalMetadata
fn wrap[T](callback: (fn(Int) T)?) Unit: return

fn apply[T, U](value: T, transform: fn(T) U) U: transform(value)

fn first() Unit:
    let offset = 7
    let _result = apply(
        value: 1,
        transform: fn outer: apply(
            value: 2, transform: fn inner: (outer + inner + offset)
        )
    )
    wrap(fn(item: Int = 4): item + offset)
