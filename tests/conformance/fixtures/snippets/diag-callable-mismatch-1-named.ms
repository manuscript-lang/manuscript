# conform: tags=diagnostics,closures,types,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def source(value: Int) -> Int: value
def exercise() -> Unit:
    let callback: Callable[[Optional[Int]], Int] = source
