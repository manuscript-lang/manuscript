// conform: tags=numbers,lexer,diagnostics,tier-core
// conform: phase=check
// conform: origin=number literal rejection
export fn main() Int {
    x := 0x
    return x
}
// expect-error: MS1001 5:12 a hexadecimal or binary literal requires digits after the prefix; write e.g. 0xFF or 0b1010
