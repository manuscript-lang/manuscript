# conform: tags=numbers,lexer,formatter,tier-core
# conform: phase=parse
# conform: origin=literals format as written
export fn main() Int:
    return 0xFF_FF + 0b1010 + 1_000
