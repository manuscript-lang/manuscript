# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def broken(value: Missing) -> Int: 1
def apply[T, U](callback: Callable[[T], U]) -> Unit: return
def exercise() -> Unit:
    apply(broken)
