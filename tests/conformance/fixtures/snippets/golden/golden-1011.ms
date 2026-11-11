// conform: tags=diagnostics
// conform: phase=check
fn choose(value: Int) Int:
    return value
fn run(fallback: Int = choose(1), hook: fn(Int) Int) Int:
    box: Array[Int] := [choose(3)]
    match fallback:
        Color.Red:
            return choose(5)
        _:
            return choose(6)
type Box:
    value: Int = choose(7)
interface Read:
    fn read(value: Int) Int
impl Read for Box:
    fn read(value: Int = choose(8)) Int:
        return choose(9)
