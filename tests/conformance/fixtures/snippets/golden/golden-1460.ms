// conform: tags=diagnostics
// conform: phase=check
fn crash() Int:
    return 1 / 0
export fn main() Int:
    values := Map[Int, Int]()
    return values.add(crash(), 1).length()
