// conform: tags=diagnostics
// conform: phase=check
fn pick(values: List[Int], index: Int) Int:
    return values.get(index)
export fn main() Int:
    return pick([1, 2, 3], 3)
