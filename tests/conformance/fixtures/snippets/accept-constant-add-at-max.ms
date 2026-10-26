# conform: tags=numbers,lists,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export def main() -> Int:
    return 9223372036854775806 + 1
