// conform: tags=diagnostics
// conform: phase=check
fn f(a Int) Int {
    match a {
    }
}
// expect-error: MS1000 4:5-4:10 match requires at least one arm; add a case pattern or '_' arm under the header
