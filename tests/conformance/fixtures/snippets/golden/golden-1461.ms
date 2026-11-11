// conform: tags=diagnostics
// conform: phase=check
fn crash() Int:
    return 1 / 0
export fn main() Int:
    values := Map[Int, Int]()
    add := values.add
    return add(value: crash(), key: 1).length()
