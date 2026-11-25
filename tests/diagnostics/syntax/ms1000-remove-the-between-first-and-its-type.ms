// conform: tags=diagnostics
// conform: phase=check
fn broken(
fn later(first: Int = 3, second: Int = first + 1) Int {
    return second
}
// expect-error: MS1000 4:15-4:16 remove the ':' between 'first' and its type; write first Type
// expect-fix: 4:15-4:16 ""
// expect-error: MS1000 10:1 unterminated delimiter '(' opened at line 3:10; add the matching ')' before the end of the file
