# conform: tags=numbers,lexer,formatter,tier-core
# conform: phase=parse
# conform: origin=literals format as written
export def main() -> Int:
    return 0xFF_FF + 0b1010 + 1_000
