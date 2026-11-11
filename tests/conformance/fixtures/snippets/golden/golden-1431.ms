// conform: tags=diagnostics
// conform: phase=check
fn %s(visits: List[Int], scoped: Bool) Int:
    %s
    var i = %d
    if scoped:
        with resource = AggregateResource(visits):
            while i < %d:
                %s
                i += 1
    else:
        while i < %d:
            %s
            i += 1
    return %s
