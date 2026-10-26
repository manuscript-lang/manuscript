# conform: tags=diagnostics,control-flow,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export def main() -> Int:
    let x = 1
    for x in [1, 2]:
        return x
    return 0
