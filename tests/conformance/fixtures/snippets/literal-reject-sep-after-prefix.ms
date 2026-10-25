# conform: tags=numbers,lexer,diagnostics,tier-core
# conform: phase=check
# conform: origin=number literal rejection
export def main() -> Int:
    let x = 0x_1
    return x
