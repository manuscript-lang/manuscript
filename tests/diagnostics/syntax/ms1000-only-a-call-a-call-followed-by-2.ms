// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    1 + 1
    return 1
}
// expect-error: MS1000 4:5-4:6 only a call, a call followed by '?', or match can be a standalone expression statement; use 'name := ...' to keep the value, 'return' to return it, or call a function
