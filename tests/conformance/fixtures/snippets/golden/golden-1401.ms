// conform: tags=diagnostics
// conform: phase=check
fn %s(visits: List[Int], scoped: Bool) String {
    b := ""
    var i = 0
    if scoped {
        with resource = Resource(visits) {
            while i < %d {
                %s
            }
        }
    } else {
        while i < %d {
            b.append(%s)
            i += 1
        }
    }
    return b.freeze()
}
// expect-error: MS1000 3:4-3:5 expected a name, found '%'
