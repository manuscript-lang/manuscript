// conform: tags=diagnostics
// conform: phase=check
fn %s(visits: List[Int], scoped: Bool) Int:
    values: List[Int] = [%s]
    var sum = 0
    if scoped:
        with resource = Resource(visits):
            for x in values:
                sum %s x
    else:
        for x in values:
            sum %s x
    return sum
