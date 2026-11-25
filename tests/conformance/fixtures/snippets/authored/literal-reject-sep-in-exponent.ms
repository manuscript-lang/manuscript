// conform: tags=numbers,lexer,diagnostics,tier-core
// conform: phase=check
// conform: origin=number literal rejection
export fn main() Int {
    x := 1e_3
    return x
}
// expect-error: MS1000 5:12 an exponent requires digits; write e.g. 1e3 or 2.5e-4
