# conform: tags=diagnostics,closures,types,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def source(value: Int) -> String: "text"
def exercise() -> Unit:
    let callback: Callable[[Int], Int] = source
