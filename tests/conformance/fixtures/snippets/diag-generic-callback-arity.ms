# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def source(first: Int, second: Int) -> Int: first + second
def apply[T](callback: Callable[[T], Int], value: T) -> Int: callback(value)
def exercise() -> Int: apply(source, 3)
