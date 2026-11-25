// conform: tags=diagnostics
// conform: phase=check
fn probe%d(visits: List[Int]) Int {
    var sum = 0
    var i = %d
    with resource = Resource(visits) {
        while i < %d {
            sum += 3
            i += 1
        }
    }
    return sum
}
// expect-error: MS1000 3:9-3:10 expected '(', found '%'; a call or parameter list starts with '('
