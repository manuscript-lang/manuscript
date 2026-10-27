# conform: tags=diagnostics,maps,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export def main() -> Int:
    let m = Map[String, Int]()
    m.set(1, 2)
    return 0
