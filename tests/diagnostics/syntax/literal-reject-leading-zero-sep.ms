// conform: tags=numbers,lexer,diagnostics,tier-core
// conform: phase=check
// conform: origin=number literal rejection
export fn main() Int {
    x := 0_1
    return x
}
// expect-error: MS1001 5:11 leading zeros are not allowed in numeric literals; write the number without them, e.g. 42 instead of 042
