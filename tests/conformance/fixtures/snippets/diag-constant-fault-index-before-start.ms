# conform: tags=diagnostics,numbers,faults,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export def main() -> Int:
    return [1, 2][-3]
