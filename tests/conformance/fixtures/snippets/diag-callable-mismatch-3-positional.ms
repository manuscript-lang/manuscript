# conform: tags=diagnostics,closures,types,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def source(_0: Int) -> String: "text"
def exercise() -> Unit:
    let callback: Callable[[Int], Int] = source
