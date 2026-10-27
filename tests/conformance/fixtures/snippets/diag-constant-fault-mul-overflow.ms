# conform: tags=diagnostics,numbers,faults,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export def main() -> Int:
    return 4611686018427387904 * 2
