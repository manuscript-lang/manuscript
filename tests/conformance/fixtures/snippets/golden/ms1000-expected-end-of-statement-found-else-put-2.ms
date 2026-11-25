// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
    if true { use() else if false: use() }
}
// expect-error: MS1000 4:21-4:25 expected end of statement, found 'else'; put one statement per line, and join operands with an operator or a comma inside brackets
