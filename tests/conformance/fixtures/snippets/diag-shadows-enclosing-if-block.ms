# conform: tags=diagnostics,control-flow,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export def main() -> Int:
    let x = 1
    if x > 0:
        let x = 2
        return x
    return 0
