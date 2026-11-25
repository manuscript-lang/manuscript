// conform: tags=numbers,lexer,diagnostics,tier-core
// conform: phase=check
// conform: origin=number literal rejection
export fn main() Int {
    x := 0o7
    return x
}
// expect-error: MS1000 5:10-5:13 invalid number 0o7; octal literals do not exist, so write the value in decimal, hexadecimal (0x) or binary (0b)
