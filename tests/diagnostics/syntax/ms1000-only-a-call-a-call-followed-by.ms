// conform: tags=diagnostics
// conform: phase=check
fn f(record Box) Int {
    var total = 12
    total 
}
// expect-error: MS1000 5:5-5:10 only a call, a call followed by '?', or match can be a standalone expression statement; use 'name := ...' to keep the value, 'return' to return it, or call a function
