# conform: tags=numbers,lexer,diagnostics,tier-core
# conform: phase=check
# conform: origin=number literal rejection
export def main() -> Int:
    let x = 1e_3
    return x
