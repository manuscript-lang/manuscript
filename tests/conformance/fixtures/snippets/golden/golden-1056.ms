// conform: tags=diagnostics
// conform: phase=check
fn work() Int:
    if value := [2, 5, 3, (-6), (-9), 1, 2, 3, 4].clone().sorted(fn(l: Int, r: Int) Int: l - r).first():
        return value
    return 0
