# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def source(value: Int) -> String: "text"
def apply[T](callback: Callable[[T], Int]) -> Unit: return
def exercise() -> Unit: apply(source)
