# conform: tags=closures,formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callback_work_test.go:93 TestCallbackProbeRetainsCapturedBindingsAndOptionalMetadata
def wrap[T](callback: Optional[Callable[[Int], T]]) -> Unit: return

def apply[T, U](value: T, transform: Callable[[T], U]) -> U: transform(value)

def first() -> Unit:
    let offset = 7
    let result = apply(
        value: 1,
        transform: lambda outer: apply(
            value: 2, transform: lambda inner: (outer + inner + offset)
        )
    )
    wrap(lambda (item: Int = 4): item + offset)
