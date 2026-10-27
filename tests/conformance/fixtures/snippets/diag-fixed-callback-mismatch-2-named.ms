# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def source(value: Int) -> Int: value
def apply[T](callback: Callable[[String], T]) -> Unit: return
def exercise() -> Unit: apply(source)
