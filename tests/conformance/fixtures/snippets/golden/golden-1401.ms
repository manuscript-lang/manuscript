// conform: tags=diagnostics
// conform: phase=check
fn %s(visits: List[Int], scoped: Bool) String:
    b := StringBuilder()
    var i = 0
    if scoped:
        with resource = Resource(visits):
            while i < %d:
                %s
    else:
        while i < %d:
            b.append(%s)
            i += 1
    return b.freeze()
