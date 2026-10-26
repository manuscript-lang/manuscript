# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def source(value: String) -> Int: value.length()
def apply[T](callback: Callable[[T], Int], value: T) -> Int: callback(value)
def exercise() -> Int: apply(source, 3)
