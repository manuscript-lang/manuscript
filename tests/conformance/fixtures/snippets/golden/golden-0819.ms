// conform: tags=diagnostics
// conform: phase=check
    return out
fn probe%d() Int:
    shapes := [Shape%d.C0(1)]
    return area%d(shapes.get(0))
