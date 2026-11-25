// conform: tags=diagnostics
// conform: phase=check
fn broken(
fn later(values: List[Int]) Void {
    field := values[holder . index]
    nested := values[indices[index]]
}
// expect-error: MS1000 4:16-4:17 remove the ':' between 'values' and its type; write values Type
// expect-fix: 4:16-4:17 ""
// expect-error: MS1000 11:1 unterminated delimiter '(' opened at line 3:10; add the matching ')' before the end of the file
