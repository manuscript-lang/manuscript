// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    var i = 0
    i++
    return i
}
// expect-error: MS1000 5:6-5:7 Manuscript has no '++' operator; write 'i += 1'
