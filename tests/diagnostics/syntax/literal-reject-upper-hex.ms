// conform: tags=numbers,lexer,diagnostics,tier-core
// conform: phase=check
// conform: origin=number literal rejection
export fn main() Int {
    x := 0X1
    return x
}
// expect-error: MS1000 5:10-5:13 invalid number 0X1; the prefix is lowercase, so write 0x1
