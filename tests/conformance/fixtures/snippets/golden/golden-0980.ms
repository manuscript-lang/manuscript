// conform: tags=diagnostics
// conform: phase=check
// prefix
fn first() Int {
    return 1
}
export fn echo(
value: String,
) String {
    return value
}
fn sum[
T,
](
left: Int,
right: Int,
) Int {
    return left + right
}
fn broken(
fn later() Int {
    return 2
}
// expect-error: MS1000 8:6-8:7 remove the ':' between 'value' and its type; write value Type
// expect-fix: 8:6-8:7 ""
// expect-error: MS1000 15:5-15:6 remove the ':' between 'left' and its type; write left Type
// expect-fix: 15:5-15:6 ""
// expect-error: MS1000 29:1 unterminated delimiter '(' opened at line 20:10; add the matching ')' before the end of the file
