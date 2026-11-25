// conform: tags=diagnostics
// conform: phase=check
fn use() Void {
    ListEntry := fn() Int => 1
    var value ListE|
}
// expect-error: MS1000 5:20-5:21 expected '=', found '|'
