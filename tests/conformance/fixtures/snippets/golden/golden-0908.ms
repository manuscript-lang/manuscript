// conform: tags=diagnostics
// conform: phase=check
fn f() Bool {
    return 1 < 2 < 3
}
// expect-error: MS1000 4:18-4:19 comparison operators cannot chain; combine two comparisons with 'and', e.g. a < b and b < c
