// conform: tags=diagnostics
// conform: phase=check
type Point {
    x Int
    y String
}
fn read(point Point) Int {
    return point.|
}
// expect-error: MS1000 8:18-8:19 expected a name, found '|'
