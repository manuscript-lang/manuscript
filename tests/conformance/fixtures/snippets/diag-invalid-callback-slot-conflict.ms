# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def broken(first: Missing, second: Int) -> Int: 1
def apply[T](callback: Callable[[T, String], Int]) -> Unit: return
def exercise() -> Unit:
    apply(broken)
