// conform: tags=numbers,lexer,diagnostics,tier-core
// conform: phase=check
// conform: origin=number literal rejection
export fn main() Int {
    x := 1_.5
    return x
}
// expect-error: MS1000 5:11 a digit separator goes between two digits; write e.g. 1_000_000 or 0xFF_FF
