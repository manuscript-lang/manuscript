// conform: tags=diagnostics
// conform: phase=check
fn first() Int {
    return 1
}
export fn answer(
    input: Int,
) Int {
    return input
}
fn broken(
// expect-error: MS1000 7:10-7:11 remove the ':' between 'input' and its type; write input Type
// expect-fix: 7:10-7:11 ""
// expect-error: MS1000 15:1 unterminated delimiter '(' opened at line 11:10; add the matching ')' before the end of the file
