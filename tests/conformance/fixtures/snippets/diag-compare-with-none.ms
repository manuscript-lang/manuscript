# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export def main() -> Int:
    let r: Optional[Int] = some(1)
    if r == none:
        return 1
    return 0
