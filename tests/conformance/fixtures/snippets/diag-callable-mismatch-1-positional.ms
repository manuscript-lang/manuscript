# conform: tags=diagnostics,closures,types,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def source(_0: Int) -> Int: _0
def exercise() -> Unit:
    let callback: Callable[[Optional[Int]], Int] = source
