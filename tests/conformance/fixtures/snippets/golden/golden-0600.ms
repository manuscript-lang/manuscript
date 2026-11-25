// conform: tags=diagnostics
// conform: phase=check
fn area(s Shape) Int {
    var out = 0
    match s {
    }
}
// expect-error: MS1000 5:5-5:10 match requires at least one arm; add a case pattern or '_' arm under the header
