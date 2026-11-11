// conform: tags=diagnostics
// conform: phase=check
fn crash(value: Int) Int:
    return 1 / value
export fn main() Int:
    value := Set[Int]().add(0)
    return value.map(crash).length()
