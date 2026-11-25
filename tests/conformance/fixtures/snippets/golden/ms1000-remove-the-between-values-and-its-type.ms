// conform: tags=diagnostics
// conform: phase=check
fn broken(
fn later(values: List[Int]) Int {
    result := match values[0] {
        number => {
            doubled := number * 2
            doubled
        }
        null => return 0
    }
    return result
}
// expect-error: MS1000 4:16-4:17 remove the ':' between 'values' and its type; write values Type
// expect-fix: 4:16-4:17 ""
// expect-error: MS1000 17:1 unterminated delimiter '(' opened at line 3:10; add the matching ')' before the end of the file
