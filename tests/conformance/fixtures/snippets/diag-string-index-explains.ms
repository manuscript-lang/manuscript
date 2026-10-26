# conform: tags=diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export def main() -> Int:
    let s = "abc"
    let c = s[0]
    return 0
